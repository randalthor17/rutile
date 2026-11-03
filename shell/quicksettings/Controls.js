// The Quick Settings controls as plain data: what each tile shows, its state from the backend, what a toggle asks
// the backend, and the same controls as launcher search results (plan 2.5's settings search, until the settings
// app, 5.1, has pages to open). `b` is the backend QuickSettingsPanel.qml describes.
.pragma library

// What each tile id shows, and the words a search finds it by besides its name.
var catalog = {
    wifi: { text: "Wi-Fi", icon: "wifi", offIcon: "wifi_off", dualTarget: true,
            keywords: ["wireless", "wlan", "network", "internet"] },
    bluetooth: { text: "Bluetooth", icon: "bluetooth", offIcon: "bluetooth_disabled", dualTarget: true,
                 keywords: ["wireless", "devices", "headphones"] },
    mic: { text: "Microphone", icon: "mic", offIcon: "mic_off", keywords: ["mute", "input", "audio"] },
    dark: { text: "Dark theme", icon: "contrast", offIcon: "contrast",
            keywords: ["dark mode", "light", "night", "appearance"] },
    airplane: { text: "Airplane mode", icon: "flight", offIcon: "flight", keywords: ["flight mode", "offline", "radios"] },
    dnd: { text: "Do not disturb", icon: "do_not_disturb_on", offIcon: "do_not_disturb_off",
           keywords: ["notifications", "silence", "quiet", "focus", "dnd"] },
    powerSaver: { text: "Power saver", icon: "energy_savings_leaf", offIcon: "energy_savings_leaf",
                  keywords: ["battery saver", "power mode", "power profile", "energy"] }
};

// The tiles a new user gets, {id, w} (w: 2 is a wide tile with its name, 1 the icon alone).
var defaultTiles = [
    { id: "wifi", w: 2 }, { id: "bluetooth", w: 2 },
    { id: "mic", w: 1 }, { id: "dark", w: 1 }, { id: "airplane", w: 1 }, { id: "dnd", w: 1 }
];

// A saved layout made safe to show: known ids once each, widths 1 or 2; the defaults for anything not a list.
function tiles(saved) {
    if (!Array.isArray(saved)) return defaultTiles;
    var seen = {};
    var out = [];
    for (var i = 0; i < saved.length; i++) {
        var t = saved[i];
        if (!t || !catalog.hasOwnProperty(t.id) || seen[t.id]) continue;
        seen[t.id] = true;
        out.push({ id: t.id, w: t.w === 2 ? 2 : 1 });
    }
    return out;
}

// The tiles not in `current`, in catalog order: what edit mode offers to add.
function addable(current) {
    var used = {};
    for (var i = 0; i < current.length; i++) used[current[i].id] = true;
    return Object.keys(catalog).filter(id => !used[id]);
}

// `current` with tile `id` added at the end: wide when it has a details side (dual target), as the defaults.
function withTile(current, id) {
    if (!catalog.hasOwnProperty(id) || current.some(t => t.id === id)) return current;
    return current.concat([{ id: id, w: catalog[id].dualTarget ? 2 : 1 }]);
}

// The sliders: a search finds them, and choosing one opens Quick Settings.
var sliders = {
    brightness: { text: "Brightness", icon: "brightness_medium", keywords: ["display", "screen", "backlight"] },
    volume: { text: "Volume", icon: "music_note", offIcon: "music_off", keywords: ["sound", "audio", "speaker", "mute"] }
};

// {active, available, secondary} for a tile.
function state(id, b) {
    if (!b) return { active: false, available: false, secondary: "" };
    switch (id) {
    case "wifi":
        return { active: b.wifiEnabled, available: b.wifiAvailable,
                 secondary: !b.wifiAvailable ? "Unavailable" : !b.wifiEnabled ? "Off" : (b.wifiName || "On") };
    case "bluetooth":
        return { active: b.bluetoothEnabled, available: b.bluetoothAvailable,
                 secondary: !b.bluetoothAvailable ? "Unavailable" : !b.bluetoothEnabled ? "Off" : (b.bluetoothDevice || "On") };
    case "mic":
        return { active: !b.micMuted, available: b.micAvailable,
                 secondary: !b.micAvailable ? "Unavailable" : b.micMuted ? "Muted" : "On" };
    case "dark":
        return { active: b.darkTheme, available: true, secondary: b.darkTheme ? "On" : "Off" };
    case "airplane": {
        var radios = b.wifiAvailable || b.bluetoothAvailable;
        var on = radios && !(b.wifiAvailable && b.wifiEnabled) && !(b.bluetoothAvailable && b.bluetoothEnabled);
        return { active: on, available: radios, secondary: on ? "On" : "Off" };
    }
    case "dnd":
        return { active: b.dnd, available: true, secondary: b.dnd ? "On" : "Off" };
    case "powerSaver":
        return { active: b.powerSaver, available: b.powerSaverAvailable,
                 secondary: !b.powerSaverAvailable ? "Unavailable" : b.powerSaver ? "On" : "Off" };
    }
    return { active: false, available: false, secondary: "" };
}

// Asks the backend to turn a tile on (`wanted`) or off.
function toggle(id, wanted, b) {
    switch (id) {
    case "wifi": b.setWifiEnabled(wanted); break;
    case "bluetooth": b.setBluetoothEnabled(wanted); break;
    case "mic": b.setMicMuted(!wanted); break;
    case "dark": b.setDarkTheme(wanted); break;
    case "airplane": b.setAirplaneMode(wanted); break;
    case "dnd": b.setDnd(wanted); break;
    case "powerSaver": b.setPowerSaver(wanted); break;
    }
}

// The controls this system has, as launcher results: {type: "setting", id: "qs:<control>", control, action
// ("toggle" or "open"), name, keywords, symbol (a Material Symbols name), status ("On", "40%")}. The status is
// shown, not searched (a network's name should not find Wi-Fi).
function searchItems(b) {
    var out = [];
    if (!b) return out;
    for (var id in catalog) {
        var s = state(id, b);
        if (!s.available) continue;
        var c = catalog[id];
        out.push({ type: "setting", id: "qs:" + id, control: id, action: "toggle", name: c.text, keywords: c.keywords,
                   symbol: s.active ? c.icon : c.offIcon, status: s.secondary });
    }
    if (b.brightnessAvailable)
        out.push({ type: "setting", id: "qs:brightness", control: "brightness", action: "open", name: sliders.brightness.text,
                   keywords: sliders.brightness.keywords, symbol: sliders.brightness.icon,
                   status: Math.round(b.brightness * 100) + "%" });
    if (b.volumeAvailable)
        out.push({ type: "setting", id: "qs:volume", control: "volume", action: "open", name: sliders.volume.text,
                   keywords: sliders.volume.keywords, symbol: b.muted ? sliders.volume.offIcon : sliders.volume.icon,
                   status: b.muted ? "Muted" : Math.round(b.volume * 100) + "%" });
    return out;
}

// Choosing a search result: a toggle flips at once ("toggled"); a slider is for the shell to open Quick
// Settings ("open").
function choose(item, b) {
    if (item.action !== "toggle") return "open";
    toggle(item.control, !state(item.control, b).active, b);
    return "toggled";
}
