// What the widget renderer (plan 4.3, D78) needs from a widget spec (widgets/spec.schema.json, D18), as plain
// functions so they test alone: bindings filled from the data sources' values, a progress value, an image's
// aspect, a tone's colors, and the checks the renderer makes itself (it draws what it can of a widget that
// tools/widget_check.py would refuse, and says what it left out). No code from a widget ever runs: a binding is
// a path into `values`, looked up, never evaluated.
.pragma library

var VERSION = 1;
var TYPES = ["row", "column", "grid", "card", "header", "tile", "heroImage", "stat", "progress", "listRow", "chip"];
var CONTAINERS = ["row", "column", "grid", "card", "tile"];
var MAX_DEPTH = 12;                 // deeper nodes are left out (a widget is a few levels; this stops runaway ones)
var MISSING = "—";                  // what a binding shows while its source has no value
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
