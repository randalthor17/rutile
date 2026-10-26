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
    airplane: { text: "Airplane mode", icon: "flight", offIcon: "flight", keywords: ["flight mode", "offline", "radios"] }
};

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
