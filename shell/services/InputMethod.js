// fcitx5 over D-Bus (D118), as plain functions so the offscreen tests check them: the busctl commands for its
// Controller1 interface and their JSON answers (`busctl --json=short`).
.pragma library

var BUS = ["busctl", "--user", "--json=short", "call", "org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1"];

// busctl's command for a Controller1 method, with its D-Bus signature and arguments when it takes some.
function call(method, signature, args) {
    return BUS.concat([method]).concat(signature ? [signature].concat(args || []) : []);
}

// The data of a busctl --json answer, or undefined.
function data(text) {
    try {
        var d = JSON.parse(String(text || ""));
        return d && Array.isArray(d.data) ? d.data : undefined;
    } catch (e) {
        return undefined;
    }
}

// The one string of an answer (CurrentInputMethod, CurrentInputMethodGroup), or "".
function string(text) {
    var d = data(text);
    return d && typeof d[0] === "string" ? d[0] : "";
}

// FullInputMethodGroupInfo's answer (sssa{sv}a(sssssssbsa{sv})): the group's input methods in its order, as
// [{id, name, label}]. `label` is short, for the pill: the method's own label, else its language, else its id.
function methods(text) {
    var d = data(text);
    var list = d && Array.isArray(d[4]) ? d[4] : [];
    return list.filter(function (m) { return Array.isArray(m) && typeof m[0] === "string" && m[0] !== ""; })
        .map(function (m) {
            var label = String(m[4] || m[5] || m[0]);
            return { id: m[0], name: String(m[1] || m[0]), label: label.toUpperCase().slice(0, 3) };
        });
}

// The method the pill shows: `current` when it is in the group, else the group's first (fcitx5 has no current one
// while no window takes text). null without methods.
function shown(list, current) {
    var all = list || [];
    return all.filter(function (m) { return m.id === current; })[0] || all[0] || null;
}

// The id after the shown one, round.
function next(list, current) {
    var all = list || [];
    if (all.length === 0) return "";
    var at = all.indexOf(shown(all, current));
    return all[(at + 1) % all.length].id;
}

// Khipro (D126): added to the current group once, when m17n lists it (home-manager links it in, D125).
var KHIPRO = "m17n_bn_khipro-dark";

// Whether AvailableInputMethods' answer (a(ssssssb)) lists `id`.
function available(text, id) {
    var d = data(text);
    var list = d && Array.isArray(d[0]) ? d[0] : [];
    return list.some(function (m) { return Array.isArray(m) && m[0] === id; });
}

// SetInputMethodGroupInfo's call for `group` with `id` added at the end, from InputMethodGroupInfo's answer
// (sa(ss): the layout and [name, layout] pairs); null when the group has it already or the answer is not one.
function withMethod(group, text, id) {
    var d = data(text);
    if (!d || typeof d[0] !== "string" || !Array.isArray(d[1])) return null;
    var items = d[1].filter(function (i) { return Array.isArray(i) && typeof i[0] === "string"; });
    if (items.some(function (i) { return i[0] === id; })) return null;
    items = items.concat([[id, ""]]);
    var args = [group, d[0], String(items.length)];
    items.forEach(function (i) { args.push(i[0], String(i[1] || "")); });
    return call("SetInputMethodGroupInfo", "ssa(ss)", args);
}

