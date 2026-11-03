// What the widget renderer (plan 4.3, D78) needs from a widget spec (widgets/spec.schema.json, D18), as plain
// functions so they test alone: bindings filled from the data sources' values, a progress value, an image's
// aspect, a tone's colors, and the checks the renderer makes itself (it draws what it can of a widget that
// tools/widget_check.py would refuse, and says what it left out). No code from a widget ever runs: a binding is
// a path into `values`, looked up, never evaluated.
.pragma library
.import "SourceCatalog.js" as Catalog

var VERSION = 1;
var TYPES = ["row", "column", "grid", "card", "header", "tile", "heroImage", "stat", "progress", "listRow", "chip"];
var CONTAINERS = ["row", "column", "grid", "card", "tile"];
var MAX_DEPTH = 12;                 // deeper nodes are left out (a widget is a few levels; this stops runaway ones)
var MISSING = "—";                  // what a binding shows while its source has no value
var MAX_ROWS = 8;                   // a listRow repeated over a list shows at most this many
var BINDING = /\{\{\s*([a-z]+(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*\}\}/g;

// The value at "source.field.sub" in `values` ({source: {field: ...}}), or undefined.
function lookup(values, path) {
    var v = values;
    var parts = path.split(".");
    for (var i = 0; i < parts.length; i++) {
        if (v === null || v === undefined || typeof v !== "object") return undefined;
        v = v[parts[i]];
    }
    return v;
}

// A list as a plain array, or null. A spec that went through a QML `var` property may hold its lists as
// array-like objects that Array.isArray refuses.
function list(v) {
    if (Array.isArray(v)) return v;
    if (v && typeof v === "object" && typeof v.length === "number") return Array.prototype.slice.call(v);
    return null;
}

// A value as text: numbers and strings as they are, a list joined, anything else (missing, an object) MISSING.
function show(v) {
    if (typeof v === "string") return v;
    if (typeof v === "number") return isFinite(v) ? String(v) : MISSING;
    if (typeof v === "boolean") return v ? "Yes" : "No";
    if (list(v)) return list(v).map(show).join(", ");
    return MISSING;
}

// The text with each {{source.field}} replaced by its value.
function resolve(text, values) {
    if (typeof text !== "string") return "";
    return text.replace(BINDING, function (m, path) { return show(lookup(values, path)); });
}

// The source.field paths a text binds, in order.
function bindingsOf(text) {
    var out = [];
    if (typeof text !== "string") return out;
    text.replace(BINDING, function (m, path) { out.push(path); return m; });
    return out;
}

// What is wrong with a binding's path against the source catalog (widgets/sources.json), or "".
function bindingProblem(path) {
    var parts = path.split(".");
    var source = Catalog.sources[parts[0]];
    if (!source) return "no source " + JSON.stringify(parts[0]);
    if (source.open) return "";
    var field = source.fields[parts[1]];
    if (!field) return parts[0] + " has no field " + JSON.stringify(parts[1]);
    if (field.type === "open") return parts.length > 2 ? "" : path + " is a document: bind a field below it";
    if (field.type === "list")
        return parts.length === 2 || (parts.length === 3 && field.item.indexOf(parts[2]) >= 0) ? ""
             : path + ": a list's items have " + field.item.join(", ");
    return parts.length === 2 ? "" : path + " has no fields below it";
}

// The sources a widget binds, each with the fields it reads: {battery: ["level", "charging"], ...}; only sources the
// catalog has (WidgetSources loads one object for each).
function sourcesUsed(spec) {
    var out = {};
    function walk(node, depth) {
        if (!node || typeof node !== "object" || depth > MAX_DEPTH) return;
        ["title", "subtitle", "label", "value", "source"].forEach(function (k) {
            bindingsOf(typeof node[k] === "string" ? node[k] : "").forEach(function (b) {
                var parts = b.split(".");
                if (!Catalog.sources[parts[0]]) return;
                var fields = out[parts[0]] || (out[parts[0]] = []);
                if (fields.indexOf(parts[1]) < 0) fields.push(parts[1]);
            });
        });
        (list(node.children) || []).forEach(function (c) { walk(c, depth + 1); });
    }
    if (spec && typeof spec === "object") walk(spec.root, 1);
    return out;
}
// A source's QML file under sources/: clock -> ClockSource.qml
function sourceFile(name) {
    return "sources/" + name.charAt(0).toUpperCase() + name.substring(1) + "Source.qml";
}

// A listRow repeats once per item when a binding of it runs through a list ({{calendar.events.title}}): the
// values each row reads, the list replaced by that item, at most MAX_ROWS; [values] when it binds no list.
function rows(node, values) {
    var texts = [node.title, node.subtitle];
    for (var t = 0; t < texts.length; t++) {
        var paths = bindingsOf(texts[t]);
        for (var p = 0; p < paths.length; p++) {
            var parts = paths[p].split(".");
            var v = values;
            for (var i = 0; i < parts.length - 1; i++) {
                if (v === null || v === undefined || typeof v !== "object") break;
                v = v[parts[i]];
                var items = list(v);
                if (items && typeof v !== "string")
                    return items.slice(0, MAX_ROWS).map(function (item) { return replaced(values, parts.slice(0, i + 1), item); });
            }
        }
    }
    return [values];
}
// `values` with the value at `parts` replaced by `item` (copies along the path only).
function replaced(values, parts, item) {
    if (parts.length === 0) return item;
    var copy = Object.assign({}, values);
    copy[parts[0]] = replaced(values ? values[parts[0]] : undefined, parts.slice(1), item);
    return copy;
}

// A progress node's value, 0..1: a number, or a binding whose value is one (a text number too); 0 otherwise.
function progress(value, values) {
    var v = value;
    if (typeof v === "string") {
        var paths = bindingsOf(v);
        v = paths.length === 1 ? Number(lookup(values, paths[0])) : NaN;
    }
    if (typeof v !== "number" || !isFinite(v)) return 0;
    return Math.max(0, Math.min(1, v));
}

// "16:9" as height / width (0.5625); 16:9 when missing or malformed.
function aspect(text) {
    var m = /^([1-9][0-9]*):([1-9][0-9]*)$/.exec(text || "");
    return m ? Number(m[2]) / Number(m[1]) : 9 / 16;
}

// A tone (a snake_case surface role) as the Colors property names to draw with:
// {fill, on (text and icons), variant (secondary text), tinted (not a surface: a progress bar draws in `on`)}.
function camel(role) {
    return role.replace(/_([a-z])/g, function (m, c) { return c.toUpperCase(); });
}
// Whether a node uses more height than its content when given it (D83): a card or tile fills it; a column or row
// does when one of its children does (the column gives it the extra, the row stretches those to its height).
function stretches(node) {
    if (!node || typeof node !== "object") return false;
    if (node.type === "card" || node.type === "tile") return true;
    if (node.type !== "column" && node.type !== "row") return false;
    return (list(node.children) || []).some(stretches);
}

// Whether a node is drawn on a surface of its own (a card or tile, or a column or row holding only one), so it needs
// no margin around it on the wallpaper (D84).
function surfaced(node) {
    if (!node || typeof node !== "object") return false;
    if (node.type === "card" || node.type === "tile") return true;
    var kids = list(node.children) || [];
    return (node.type === "column" || node.type === "row") && kids.length === 1 && surfaced(kids[0]);
}

function toneColors(tone) {
    var fill = camel(tone || "surface_container");
    if (fill === "background") return { fill: fill, on: "backgroundOn", variant: "surfaceVariantOn", tinted: false };
    if (fill === "inverseSurface") return { fill: fill, on: "inverseOnSurface", variant: "inverseOnSurface", tinted: true };
    if (fill.indexOf("surface") === 0) return { fill: fill, on: "surfaceOn", variant: "surfaceVariantOn", tinted: false };
    // primary, primaryContainer, secondary, ... : their own "On" role, for both
    return { fill: fill, on: fill + "On", variant: fill + "On", tinted: true };
}

// What the renderer leaves out of a widget, as messages ("root.children[1]: unknown type 'map'"); empty when it
// draws all of it.
function problems(spec) {
    var out = [];
    if (!spec || typeof spec !== "object") return ["not a widget"];
    if (spec.version !== VERSION) out.push("version " + JSON.stringify(spec.version) + ", this shell reads " + VERSION);
    function walk(node, where, depth) {
        if (depth > MAX_DEPTH) return out.push(where + ": deeper than " + MAX_DEPTH + " levels, left out");
        if (!node || typeof node !== "object" || TYPES.indexOf(node.type) < 0)
            return out.push(where + ": unknown type " + JSON.stringify(node && node.type) + ", left out");
        ["title", "subtitle", "label", "value", "source"].forEach(function (k) {
            bindingsOf(typeof node[k] === "string" ? node[k] : "").forEach(function (b) {
                var problem = bindingProblem(b);
                if (problem) out.push(where + "." + k + ": " + problem + ", shows " + MISSING);
            });
        });
        if (CONTAINERS.indexOf(node.type) >= 0) {
            var children = list(node.children);
            if (!children) return out.push(where + ": no children");
            for (var i = 0; i < children.length; i++)
                walk(children[i], where + ".children[" + i + "]", depth + 1);
        }
    }
    walk(spec.root, "root", 1);
    return out;
}

// Whether the renderer draws a node (a known type, not too deep).
function drawable(node, depth) {
    return !!node && typeof node === "object" && TYPES.indexOf(node.type) >= 0 && depth <= MAX_DEPTH;
}
