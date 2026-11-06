// What the shelf shows, as plain data so it is tested offscreen: the pinned apps (launchers), and the open
// windows grouped by workspace, one entry per window (as Noctalia's taskbar does). ShelfBackend.qml feeds it
// desktop entries and niri's workspaces (NiriState.groups), or Quickshell's toplevels where niri is not running.
.pragma library

// Default pins while the shelf.pins setting is unset: the first installed app of each group.
var defaultPinGroups = [
    ["org.gnome.Nautilus", "thunar", "org.kde.dolphin", "nemo", "pcmanfm"],
    ["firefox", "chromium-browser", "chromium", "google-chrome", "brave-browser"],
    ["com.mitchellh.ghostty", "foot", "kitty", "Alacritty", "org.wezfurlong.wezterm", "org.gnome.Console"]
];

// The ids to pin: `saved` (the shelf.pins setting, a list of ids, with or without ".desktop") if set, else the
// first id of each default group that `exists(id)` says is installed.
function pins(saved, exists) {
    // "firefox.desktop" names the same app as "firefox" (desktop ids are written both ways)
    if (Array.isArray(saved)) return saved.map(s => String(s).replace(/\.desktop$/, "")).filter(s => s !== "");
    var out = [];
    for (var g = 0; g < defaultPinGroups.length; g++) {
        var hit = defaultPinGroups[g].find(id => exists(id));
        if (hit) out.push(hit);
    }
    return out;
}

// `ids` with `id` added at the end, or without it if it is there: what Pin and Unpin in the launcher save.
function togglePin(ids, id) {
    return ids.indexOf(id) >= 0 ? ids.filter(x => x !== id) : ids.concat([id]);
}

// niri's groups ([{id, idx, name, active, windows: [{id, appId, title, focused}]}]) with each window's name and
// icon from its desktop entry: lookup(appId) gives {name, icon} or null (then the app id names it, no icon).
function decorate(groups, lookup) {
    return groups.map(g => ({
        id: g.id, idx: g.idx, name: g.name, active: g.active,
        windows: g.windows.map(w => {
            var e = lookup(w.appId);
            return { id: w.id, appId: w.appId, title: w.title, focused: w.focused,
                     name: e && e.name ? e.name : (w.appId || w.title), icon: e && e.icon ? e.icon : "" };
        })
    }));
}

// Without niri (another compositor): every toplevel in one group without a workspace number.
// windows: [{appId, title, activated}]; the window id is its index.
function ungrouped(windows) {
    if (windows.length === 0) return [];
    return [{ id: -1, idx: 0, name: "", active: false,
              windows: windows.map((w, i) => ({ id: i, appId: w.appId, title: w.title, focused: !!w.activated })) }];
}

// A shelf button's right-click menu (D72) as Menu items. `info`: {window (a window, not a pin), entry (it has a
// desktop entry), actions (its desktop actions' names), pinned, editable (pins not set in Nix)}. Ids: "open",
// "action:<n>", "pin", "unpin", "close".
function menuItems(info) {
    var out = [];
    if (info.entry) out.push({ id: "open", text: info.window ? "New window" : "Open", icon: info.window ? "open_in_new" : "launch" });
    var actions = info.entry ? info.actions || [] : [];
    for (var i = 0; i < actions.length; i++) out.push({ id: "action:" + i, text: actions[i] });
    if (info.entry && info.editable) {
        if (out.length) out.push({ id: "sepPin", separator: true });
        out.push(info.pinned ? { id: "unpin", text: "Unpin", icon: "keep_off" } : { id: "pin", text: "Pin to shelf", icon: "keep" });
    }
    if (info.window) {
        if (out.length) out.push({ id: "sepClose", separator: true });
        out.push({ id: "close", text: "Close window", icon: "close" });
    }
    return out;
}

// `ids` with the one at `index` moved by `delta` (-1 earlier, +1 later); unchanged at an end.
function move(ids, index, delta) {
    var to = index + delta;
    if (index < 0 || index >= ids.length || to < 0 || to >= ids.length) return ids.slice();
    var out = ids.slice();
    var it = out.splice(index, 1)[0];
    out.splice(to, 0, it);
    return out;
}

// The desktop ids with a window open in `groups` (decorate()'s input, every output's): entryId(appId) gives a
// window's desktop id, or "" when it has none. A pin with one is marked as running.
function runningIds(groups, entryId) {
    var out = [];
    groups.forEach(g => g.windows.forEach(w => {
        var id = w.appId ? entryId(w.appId) : "";
        if (id && out.indexOf(id) < 0) out.push(id);
    }));
    return out;
}

// Where a pin dragged from `from` lands after moving `dx` pixels along buttons `slot` apart: an index in the pins.
function dropIndex(from, dx, slot, count) {
    if (!(slot > 0)) return from;
    return Math.max(0, Math.min(count - 1, from + Math.round(dx / slot)));
}

// How far the pin at `index` steps aside while one is dragged from `from` to `to`: -1, 0 or +1 slots.
function dragShift(index, from, to) {
    if (from < 0 || index === from) return 0;
    if (from < to && index > from && index <= to) return -1;
    if (to < from && index >= to && index < from) return 1;
    return 0;
}
