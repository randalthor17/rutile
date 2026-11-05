// The desktop widget grid's saved data (plan 4.4, D81), as pure functions. Each screen (by output name) has its
// own list of placed widgets, [{id, path, w, h, col, row}] in cells, kept in state.json as `desktop.widgets`.
.pragma library

// What a widget gets when it is added: a size most widgets fit, which the grid shrinks when there is less room.
var NEW_SIZE = { w: 4, h: 3 };

function placed(all, screen) {
    var list = all && all[screen];
    return Array.isArray(list) ? list.filter(function (i) { return i && typeof i.path === "string"; }) : [];
}

// `all` with `screen`'s list replaced; a screen with nothing placed is left out.
function withScreen(all, screen, items) {
    var out = {};
    for (var k in (all || {}))
        if (k !== screen) out[k] = all[k];
    if (items.length > 0) out[screen] = items;
    return out;
}

// Every widget file placed on any screen, once each, so each is read once however many screens show it.
function paths(all) {
    var out = [];
    for (var k in (all || {}))
        placed(all, k).forEach(function (i) { if (out.indexOf(i.path) < 0) out.push(i.path); });
    return out.sort();
}

function baseName(path) {
    return String(path).replace(/^.*\//, "").replace(/\.json$/, "");
}

// An id for a new widget from `path`, unique among `items`: the file's name, then -2, -3...
function newId(items, path) {
    var base = baseName(path) || "widget";
    var taken = items.map(function (i) { return i.id; });
    var id = base;
    for (var n = 2; taken.indexOf(id) >= 0; n++) id = base + "-" + n;
    return id;
}

function withAdded(items, path, size) {
    return items.concat([{ id: newId(items, path), path: path, w: size.w, h: size.h }]);
}

function withoutIndex(items, index) {
    return items.filter(function (i, n) { return n !== index; });
}

// `all` with widget `index` of screen `from` moved to screen `to` at `size` (the room its grid found there), where
// that grid finds free cells. It keeps its id unless `to` has one already; its place on `from` is not kept.
function withMoved(all, from, index, to, size) {
    var source = placed(all, from);
    var item = source[index];
    if (!item || from === to) return all;
    var target = placed(all, to);
    var moved = {};
    for (var k in item)
        if (k !== "col" && k !== "row") moved[k] = item[k];
    if (target.some(function (i) { return i.id === item.id; })) moved.id = newId(target, item.path);
    moved.w = size.w;
    moved.h = size.h;
    return withScreen(withScreen(all, from, withoutIndex(source, index)), to, target.concat([moved]));
}

// The widgets that can be added, from the scan's output: each file as \x1e path \x1f contents. A file that does
// not parse is listed by its file name, so it can still be placed and fixed while it shows.
function scanned(text) {
    var out = [];
    String(text).split("\x1e").forEach(function (part) {
        var cut = part.indexOf("\x1f");
        if (cut <= 0) return;
        var path = part.substring(0, cut);
        var name = "";
        try { name = JSON.parse(part.substring(cut + 1)).name || ""; } catch (e) { }
        if (out.some(function (a) { return a.path === path; })) return;
        out.push({ path: path, name: typeof name === "string" && name !== "" ? name : baseName(path) });
    });
    return out;
}

// A widget file's text as a spec, or null.
function parse(text) {
    try {
        var spec = JSON.parse(text);
        return spec && typeof spec === "object" ? spec : null;
    } catch (e) {
        return null;
    }
}
