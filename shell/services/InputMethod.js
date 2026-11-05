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
