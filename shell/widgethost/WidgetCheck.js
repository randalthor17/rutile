// The widget check in the shell (plan 4.6, D85): tools/widget_check.py's rules for one widget, ported so that
// `rutile-shell widgets check` and `install` work where the package has no Python. A widget is checked against the
// spec's JSON Schema (SpecSchema.js, generated from widgets/spec.schema.json; the same subset of 2020-12 the Python
// implements) and its bindings against the data sources (SourceCatalog.js). Problems are {path, message}, with the
// path written $.root.children[0].title and the messages worded as the Python's: the qml tests run both on the same
// cases and compare. Pure JavaScript, no QML.
.pragma library
.import "SpecSchema.js" as SpecSchema
.import "SourceCatalog.js" as Catalog

var MAX_PROBLEMS = 15;
var NODE_TYPES = ["row", "column", "grid", "card", "header", "tile", "heroImage", "stat", "progress", "listRow", "chip"];
var BINDING = /\{\{\s*([^{}]*?)\s*\}\}/g;

function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }
// `name` as a key of the object itself (`in` would also find "constructor" and the like)
function has(o, name) { return Object.prototype.hasOwnProperty.call(o, name); }
function isInteger(v) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v; }
var TYPES = {
    object: isObject,
    array: function (v) { return Array.isArray(v); },
    string: function (v) { return typeof v === "string"; },
    boolean: function (v) { return typeof v === "boolean"; },
    "null": function (v) { return v === null; },
    integer: isInteger,
    number: function (v) { return typeof v === "number" && isFinite(v); }
};

// Python's json.dumps: ", " and ": " between items, non-ASCII escaped.
function dumps(v) {
    if (Array.isArray(v)) return "[" + v.map(dumps).join(", ") + "]";
    if (isObject(v)) return "{" + Object.keys(v).map(function (k) { return dumps(k) + ": " + dumps(v[k]); }).join(", ") + "}";
    if (v === undefined) return "null";
    return JSON.stringify(v).replace(/[\u0080-￿]/g, function (c) {
        return "\\u" + ("000" + c.charCodeAt(0).toString(16)).slice(-4);
    });
}
function short(v) {
    var text = dumps(v);
    return text.length <= 60 ? text : text.substring(0, 57) + "...";
}
// Python's repr of a string (the field names in messages).
function repr(s) {
    s = String(s);
    return s.indexOf("'") >= 0 && s.indexOf('"') < 0 ? '"' + s + '"' : "'" + s.replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'";
}
// characters as Python counts them: a surrogate pair is one (Qt's Array.from(string) splits them)
function chars(s) { return s.length - (s.match(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g) || []).length; }
function equal(a, b) { return dumps(a) === dumps(b); }

function pathString(path) {
    var out = "$";
    for (var i = 0; i < path.length; i++)
        out += typeof path[i] === "number" ? "[" + path[i] + "]" : "." + path[i];
    return out;
}

function resolve(root, ref) {
    var node = root;
    var parts = ref.substring(2).split("/");
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i].replace(/~1/g, "/").replace(/~0/g, "~");
        if (!isObject(node) || !has(node, part)) throw new Error("$ref " + repr(ref) + " does not resolve");
        node = node[part];
    }
    return node;
}

function problem(path, message) { return { path: path, message: message }; }

// Problems as {path (an array), message}; empty when `value` matches `schema`.
function validate(value, schema, root, path, depth) {
    path = path || [];
    depth = depth || 0;
    if (depth > 64) return [problem(path, "nesting too deep (a $ref loop?)")];
    if (schema === true) return [];
    if (schema === false) return [problem(path, "no value is allowed here")];
    var errs = [];
    var add = function (list) { errs = errs.concat(list); };
    if ("$ref" in schema) add(validate(value, resolve(root, schema["$ref"]), root, path, depth + 1));
    if ("type" in schema) {
        var types = Array.isArray(schema.type) ? schema.type : [schema.type];
        if (!types.some(function (t) { return TYPES[t](value); }))
            return errs.concat([problem(path, "expected " + types.join(" or ") + ", got " + short(value))]);
    }
    if ("const" in schema && !equal(value, schema["const"]))
        errs.push(problem(path, "must be " + short(schema["const"]) + ", got " + short(value)));
    if ("enum" in schema && !schema["enum"].some(function (e) { return equal(e, value); })) {
        var allowed = schema["enum"].slice(0, 12).map(short).join(", ") + (schema["enum"].length > 12 ? ", ..." : "");
        errs.push(problem(path, short(value) + " is not one of: " + allowed));
    }
    if (typeof value === "string") {
        if (chars(value) < (schema.minLength || 0)) errs.push(problem(path, "shorter than " + schema.minLength + " characters"));
        if ("maxLength" in schema && chars(value) > schema.maxLength)
            errs.push(problem(path, "longer than " + schema.maxLength + " characters"));
        if ("pattern" in schema && !new RegExp(schema.pattern, "u").test(value))
            errs.push(problem(path, short(value) + " does not match pattern " + schema.pattern));
    }
    if (TYPES.number(value)) {
        var bounds = [["minimum", function (v, b) { return v < b; }], ["maximum", function (v, b) { return v > b; }],
                      ["exclusiveMinimum", function (v, b) { return v <= b; }],
                      ["exclusiveMaximum", function (v, b) { return v >= b; }]];
        bounds.forEach(function (k) {
            if (k[0] in schema && k[1](value, schema[k[0]]))
                errs.push(problem(path, value + " violates " + k[0] + " " + schema[k[0]]));
        });
    }
    if (Array.isArray(value)) {
        if (value.length < (schema.minItems || 0)) errs.push(problem(path, "needs at least " + schema.minItems + " item(s)"));
        if ("maxItems" in schema && value.length > schema.maxItems)
            errs.push(problem(path, "allows at most " + schema.maxItems + " item(s)"));
        if ("items" in schema)
            value.forEach(function (item, i) { add(validate(item, schema.items, root, path.concat([i]), depth + 1)); });
    }
    if (isObject(value)) {
        var props = schema.properties || {};
        (schema.required || []).forEach(function (name) {
            if (!has(value, name)) errs.push(problem(path, "missing required field " + repr(name)));
        });
        var extra = has(schema, "additionalProperties") ? schema.additionalProperties : true;
        Object.keys(value).forEach(function (name) {
            if (has(props, name)) {
                add(validate(value[name], props[name], root, path.concat([name]), depth + 1));
            } else if (extra === false) {
                var names = Object.keys(props).sort();
                errs.push(problem(path, "unknown field " + repr(name) + " (allowed here: " + (names.join(", ") || "none") + ")"));
            } else if (isObject(extra)) {
                add(validate(value[name], extra, root, path.concat([name]), depth + 1));
            }
        });
    }
    (schema.allOf || []).forEach(function (sub) { add(validate(value, sub, root, path, depth + 1)); });
    var shortest = function (results) {
        return results.reduce(function (a, b) { return b.length < a.length ? b : a; });
    };
    if ("anyOf" in schema) {
        var any = schema.anyOf.map(function (sub) { return validate(value, sub, root, path, depth + 1); });
        if (any.every(function (r) { return r.length > 0; })) add(shortest(any));
    }
    if ("oneOf" in schema) {
        var one = schema.oneOf.map(function (sub) { return validate(value, sub, root, path, depth + 1); });
        var passing = one.filter(function (r) { return r.length === 0; }).length;
        if (passing === 0) add(explainOneOf(value, schema.oneOf, one, root, path, shortest));
        else if (passing > 1) errs.push(problem(path, "matches " + passing + " of the oneOf branches; make them mutually exclusive"));
    }
    if ("not" in schema && validate(value, schema["not"], root, path, depth + 1).length === 0)
        errs.push(problem(path, "matches a schema it must not match"));
    if ("if" in schema) {
        var branch = validate(value, schema["if"], root, path, depth + 1).length === 0 ? "then" : "else";
        if (branch in schema) add(validate(value, schema[branch], root, path, depth + 1));
    }
    return errs;
}

// For a node with a `type`, the errors of the branch for that type, not of every branch.
function explainOneOf(value, branches, results, root, path, shortest) {
    if (isObject(value) && has(value, "type")) {
        for (var i = 0; i < branches.length; i++) {
            var target = "$ref" in branches[i] ? resolve(root, branches[i]["$ref"]) : branches[i];
            var t = target.properties && target.properties.type;
            if (t && equal(t["const"], value.type)) return results[i];
        }
        return [problem(path, "no node type " + short(value.type) + "; known: " + NODE_TYPES.join(", "))];
    }
    return shortest(results);
}

// Every string in a value, with its path, in order.
function strings(value, path, out) {
    if (typeof value === "string") out.push({ path: path, text: value });
    else if (Array.isArray(value)) value.forEach(function (v, i) { strings(v, path.concat([i]), out); });
    else if (isObject(value)) Object.keys(value).forEach(function (k) { strings(value[k], path.concat([k]), out); });
    return out;
}

function sourceNames() { return Object.keys(Catalog.sources).sort(); }

// Why `fields` (the path after the source) names nothing in the catalog, or "".
function fieldProblem(source, fields) {
    var entry = Catalog.sources[source];
    if (entry.open) return "";
    var known = Object.keys(entry.fields);
    var name = fields[0];
    if (!has(entry.fields, name)) return source + " has no field " + repr(name) + "; it has: " + known.join(", ");
    var f = entry.fields[name];
    if (f.type === "open")
        return fields.length > 1 ? "" : source + "." + name + " is a document: bind a field below it, e.g. " + source + "." + name + ".x";
    if (f.type === "list") {
        if (fields.length === 1) return "";
        if (f.item.indexOf(fields[1]) < 0 || fields.length > 2)
            return source + "." + name + " is a list; bind one of its items' fields: " + f.item.join(", ");
        return "";
    }
    if (fields.length > 1) return source + "." + name + " is a " + f.type + ", with no fields below it";
    return "";
}

function bindingProblems(widget) {
    var errs = [];
    var used = [];
    var names = sourceNames();
    var ok = new RegExp("^(" + names.join("|") + ")\\.[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$");
    var body = {};
    if (isObject(widget)) Object.keys(widget).forEach(function (k) { if (k !== "sources") body[k] = widget[k]; });
    strings(isObject(widget) ? body : widget, [], []).forEach(function (s) {
        var m;
        BINDING.lastIndex = 0;
        while ((m = BINDING.exec(s.text)) !== null) {
            if (!ok.test(m[1])) {
                errs.push(problem(s.path, "binding " + repr(m[0]) + " must be {{source.field}} with a source from: " +
                                          names.join(", ") + " (no code, no spaces)"));
                continue;
            }
            var parts = m[1].split(".");
            if (used.indexOf(parts[0]) < 0) used.push(parts[0]);
            var why = fieldProblem(parts[0], parts.slice(1));
            if (why) errs.push(problem(s.path, "binding " + repr(m[0]) + ": " + why));
        }
    });
    var options = isObject(widget) && isObject(widget.sources) ? widget.sources : {};
    var defs = SpecSchema.schema.$defs.sources.properties;
    used.sort().forEach(function (source) {
        var need = (defs[source] && defs[source].required) || [];
        if (need.length && !isObject(options[source]))
            errs.push(problem(["sources"], "binds " + source + " but gives no sources." + source + " with " + need.join(", ")));
    });
    return errs;
}

// A widget's problems, at most MAX_PROBLEMS and then a note: [{path: "$.root...", message}].
function check(widget) {
    var all = validate(widget, SpecSchema.schema, SpecSchema.schema).concat(bindingProblems(widget));
    var out = all.slice(0, MAX_PROBLEMS).map(function (p) { return { path: pathString(p.path), message: p.message }; });
    if (all.length > MAX_PROBLEMS)
        out.push({ path: "$", message: "... and " + (all.length - MAX_PROBLEMS) + " more; fix these first" });
    return out;
}

// A widget file's text checked: {ok, problems}; text that is not JSON is one problem.
function checkText(text) {
    var widget;
    try {
        widget = JSON.parse(text);
    } catch (e) {
        return { ok: false, problems: [{ path: "$", message: "not valid JSON: " + e.message }] };
    }
    var problems = check(widget);
    return { ok: problems.length === 0, problems: problems };
}

// The text report, as widget_check.py prints it: "FILE: $.path: message" lines, then ok or FAILED.
function report(file, result) {
    var lines = result.problems.map(function (p) {
        return p.message.indexOf("... and ") === 0 ? file + ": " + p.message : file + ": " + p.path + ": " + p.message;
    });
    lines.push(result.ok ? "ok: " + file : "FAILED: " + file + " (" + result.problems.length + " problem(s))");
    return lines.join("\n");
}
