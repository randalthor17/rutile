// What Quick Settings' detail pages (Wi-Fi networks, Bluetooth devices; plan 2.6) list, as plain data, so the
// order, the words and what a click does test without NetworkManager or BlueZ. The backend hands over plain
// lists: networks {name, signal (0..1), secure, psk (a password is enough), connected, known, busy} and devices
// {address, name (the address when it has none), named, icon (BlueZ's: audio-headset...), connected, paired, busy,
// battery (0..1, or -1)}.
.pragma library

// Networks to list: named ones once each (the strongest of a name's access points), the connected first, then
// those known, then by signal.
function networks(list) {
    var byName = {};
    for (var i = 0; i < (list || []).length; i++) {
        var n = list[i];
        if (!n || !n.name) continue;
        var had = byName[n.name];
        if (!had || n.connected || (!had.connected && n.signal > had.signal)) byName[n.name] = n;
    }
    return Object.keys(byName).map(k => byName[k]).sort((a, b) =>
        (b.connected - a.connected) || (b.known - a.known) || (b.signal - a.signal) || a.name.localeCompare(b.name));
}

// The Material Symbol for a signal strength.
function signalIcon(signal) {
    if (signal >= 0.75) return "network_wifi";
    if (signal >= 0.5) return "network_wifi_3_bar";
    if (signal >= 0.25) return "network_wifi_2_bar";
    return "network_wifi_1_bar";
}

function networkStatus(n) {
    if (n.busy) return n.connected ? "Disconnecting…" : "Connecting…";
    if (n.connected) return "Connected";
    if (n.known) return "Saved";
    return n.secure ? "Secured" : "Open";
}

// What a click on a network does: "disconnect", "connect", "password" (ask for one first), or "" (none: a
// network that needs more than a password, such as enterprise sign-in, or one busy already).
function networkAction(n) {
    if (n.busy) return "";
    if (n.connected) return "disconnect";
    if (n.known || !n.secure) return "connect";
    return n.psk ? "password" : "";
}

// Devices to list: the connected first, then the paired, then by name; nameless ones (an address only) last.
function devices(list) {
    return (list || []).filter(d => !!d && !!d.address).slice().sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired) || ((!a.named) - (!b.named)) ||
        a.name.localeCompare(b.name));
}

// BlueZ's icon name (freedesktop's) as a Material Symbol.
function deviceIcon(icon) {
    var map = {
        "audio-headset": "headset_mic", "audio-headphones": "headphones", "audio-card": "speaker",
        "input-keyboard": "keyboard", "input-mouse": "mouse", "input-gaming": "sports_esports",
        "input-tablet": "stylus", "phone": "smartphone", "computer": "computer", "camera-video": "videocam",
        "printer": "print"
    };
    return map[icon] ?? "bluetooth";
}

function deviceStatus(d) {
    var battery = d.battery >= 0 ? " · " + Math.round(d.battery * 100) + "%" : "";
    if (d.busy) return d.connected ? "Disconnecting…" : (d.paired ? "Connecting…" : "Pairing…");
    if (d.connected) return "Connected" + battery;
    return d.paired ? "Paired" : "Not paired";
}

// "disconnect", "connect" (pairs first when not paired), or "" while busy.
function deviceAction(d) {
    if (d.busy) return "";
    return d.connected ? "disconnect" : "connect";
}
