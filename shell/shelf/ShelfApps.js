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

// The ids to pin: `saved` (the shelf.pins setting, a list of ids) if set, else the first id of each default
// group that `exists(id)` says is installed.
function pins(saved, exists) {
    if (Array.isArray(saved)) return saved.filter(s => s !== "");
    var out = [];
    for (var g = 0; g < defaultPinGroups.length; g++) {
        var hit = defaultPinGroups[g].find(id => exists(id));
        if (hit) out.push(hit);
    }
    return out;
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
