// What the shelf shows: pinned apps in order, then running apps that are not pinned, each with whether it runs
// and whether one of its windows is active. Plain data in and out, so it is tested offscreen; ShelfBackend.qml
// feeds it Quickshell's desktop entries and toplevels.
.pragma library

// Default pins until saved settings (plan 2.5): the first installed app of each group.
var defaultPinGroups = [
    ["org.gnome.Nautilus", "thunar", "org.kde.dolphin", "nemo", "pcmanfm"],
    ["firefox", "chromium-browser", "chromium", "google-chrome", "brave-browser"],
    ["com.mitchellh.ghostty", "foot", "kitty", "Alacritty", "org.wezfurlong.wezterm", "org.gnome.Console"]
];

// The ids to pin: `override` ("a,b,c", e.g. from RUTILE_SHELF_PINS) if set, else the first id of each default
// group that `exists(id)` says is installed.
function pins(override, exists) {
    if (override) return override.split(",").map(s => s.trim()).filter(s => s !== "");
    var out = [];
    for (var g = 0; g < defaultPinGroups.length; g++) {
        var hit = defaultPinGroups[g].find(id => exists(id));
        if (hit) out.push(hit);
    }
    return out;
}

function norm(s) {
    return String(s || "").toLowerCase().replace(/\.desktop$/, "");
}

// Whether a window's app id belongs to a desktop entry {id, startupClass}: the id, the startup class, or the last
// part of a reverse-DNS id ("org.gnome.Nautilus" for "nautilus").
function matches(entry, appId) {
    var a = norm(appId);
    if (a === "") return false;
    var id = norm(entry.id);
    return a === id || a === norm(entry.startupClass) || a === id.split(".").pop();
}

// pinned: [{id, name, icon, startupClass}] in order; windows: [{appId, activated}]; lookup(appId) gives the entry
// for a window no pinned app claims (or null: it is shown under its app id). Returns
// [{id, name, icon, pinned, running, active, windows: [indices into `windows`]}].
function build(pinned, windows, lookup) {
    var items = pinned.map(e => ({ id: e.id, name: e.name, icon: e.icon, pinned: true, running: false,
                                   active: false, windows: [], entry: e }));
    for (var w = 0; w < windows.length; w++) {
        var win = windows[w];
        var item = items.find(it => matches(it.entry, win.appId));
        if (!item) {
            var e = lookup(win.appId) || { id: win.appId, name: win.appId, icon: "", startupClass: win.appId };
            item = items.find(it => !it.pinned && it.id === e.id);
            if (!item) {
                item = { id: e.id, name: e.name, icon: e.icon, pinned: false, running: false, active: false,
                         windows: [], entry: e };
                items.push(item);
            }
        }
        item.running = true;
        item.active = item.active || !!win.activated;
        item.windows.push(w);
    }
    return items.map(it => ({ id: it.id, name: it.name, icon: it.icon, pinned: it.pinned, running: it.running,
                              active: it.active, windows: it.windows }));
}

// Which window a click on a running app brings forward: the one after the active one (cycling), else the first.
function nextWindow(item, windows) {
    if (item.windows.length === 0) return -1;
    var at = item.windows.findIndex(i => windows[i].activated);
    return item.windows[(at + 1) % item.windows.length];
}
