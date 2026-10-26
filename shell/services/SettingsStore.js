// The settings as plain data (D45), so they are tested offscreen: the schema's leaves, which value wins
// (managed.json, then settings.json, then the default), and copies of a file's object with one key changed.
// Keys are dotted paths ("motion.speed"); the files nest them ({"motion": {"speed": 1}}). Settings.qml feeds
// it the files' text.
.pragma library

// {"motion.speed": leafSchema, ...}: every setting in the schema
function leaves(schema) {
    var out = {};
    function walk(prefix, node) {
        for (var name in node.properties) {
            var child = node.properties[name];
            var key = prefix + name;
            if (child.type === "object") walk(key + ".", child);
            else out[key] = child;
        }
    }
    walk("", schema);
    return out;
}

function scalarValid(leaf, value) {
    switch (leaf.type) {
    case "boolean": return typeof value === "boolean";
    case "integer": return Number.isInteger(value);
    case "number": return typeof value === "number" && isFinite(value);
    case "string": return typeof value === "string";
    }
    return false;
}

// Whether `value` fits the leaf: its type, enum and limits (tools/gen_settings.py's value_ok).
function valid(leaf, value) {
    if (leaf.type === "array")
        return Array.isArray(value) && value.every(function (v) { return valid(leaf.items, v); });
    if (!scalarValid(leaf, value)) return false;
    if (leaf.enum !== undefined && leaf.enum.indexOf(value) < 0) return false;
    if (leaf.minimum !== undefined && value < leaf.minimum) return false;
    return !(leaf.maximum !== undefined && value > leaf.maximum);
}

// The value at `key` in a file's object, or undefined.
function get(obj, key) {
    var parts = key.split(".");
    for (var i = 0; i < parts.length; i++) {
        if (obj === null || typeof obj !== "object" || Array.isArray(obj) || !(parts[i] in obj)) return undefined;
        obj = obj[parts[i]];
    }
    return obj;
}

// A copy of `obj` with `key` set to `value`; with `value` undefined, without `key` (and without the objects
// that leaves empty). Everything else, keys the schema does not know included, is kept.
function withValue(obj, key, value) {
    var parts = key.split(".");
    function put(node, i) {
        var copy = {};
        for (var k in node) copy[k] = node[k];
        var name = parts[i];
        if (i === parts.length - 1) {
            if (value === undefined) delete copy[name];
            else copy[name] = value;
        } else {
            var child = copy[name];
            var next = put(child !== null && typeof child === "object" && !Array.isArray(child) ? child : {}, i + 1);
            if (Object.keys(next).length === 0) delete copy[name];
            else copy[name] = next;
        }
        return copy;
    }
    return put(obj || {}, 0);
}

// Parses a file's text: {data} with the object ("" or only whitespace is an empty file), or {error}.
function parse(text) {
    if (!text || !text.trim()) return { data: {} };
    try {
        var data = JSON.parse(text);
        if (data === null || typeof data !== "object" || Array.isArray(data))
            return { error: "the file must hold a JSON object" };
        return { data: data };
    } catch (e) {
        return { error: e.message };
    }
}

// What the shell uses: {values: {key: value} (undefined where unset with no default), managed: {key: true},
// problems: ["file: key: ..."]}. A value that does not fit the schema is skipped, with a problem.
function resolve(schema, user, managed) {
    var all = leaves(schema);
    var out = { values: {}, managed: {}, problems: [] };
    for (var key in all) {
        var leaf = all[key];
        var value = leaf["default"];
        var layers = [["settings.json", user], ["managed.json", managed]];
        for (var i = 0; i < layers.length; i++) {
            var v = get(layers[i][1], key);
            if (v === undefined) continue;
            if (!valid(leaf, v)) {
                out.problems.push(layers[i][0] + ": " + key + ": " + JSON.stringify(v) + " does not fit the schema");
                continue;
            }
            value = v;
            if (i === 1) out.managed[key] = true;
        }
        out.values[key] = value;
    }
    return out;
}

// The text written for a file's object: indented, as people edit it.
function format(obj) {
    return JSON.stringify(obj, null, 2) + "\n";
}
