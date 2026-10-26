// Material Symbols names for the status pill, from the backend's state. Kept apart so they are tested offscreen.
.pragma library

// "" means no network icon (no Wi-Fi device and no cable).
function network(b) {
    if (b.wiredConnected) return "settings_ethernet";      // Android's ethernet icon; Material Symbols has no RJ45 jack
    if (!b.wifiAvailable) return "";
    if (!b.wifiEnabled) return "wifi_off";
    if (!b.wifiName) return "signal_wifi_0_bar";
    var s = b.wifiSignal;
    return s >= 0.75 ? "network_wifi" : s >= 0.5 ? "network_wifi_3_bar" : s >= 0.25 ? "network_wifi_2_bar" : "network_wifi_1_bar";
}

function volume(b) {
    if (!b.volumeAvailable) return "";
    if (b.muted || b.volume <= 0) return "volume_off";
    return b.volume < 0.5 ? "volume_down" : "volume_up";
}

// battery_0_bar .. battery_6_bar, battery_full; charging: battery_charging_20 .. _90, battery_charging_full.
function battery(b) {
    if (!b.batteryAvailable) return "";
    var p = Math.max(0, Math.min(1, b.battery));
    if (b.charging) {
        if (p >= 0.95) return "battery_charging_full";
        var steps = [20, 30, 50, 60, 80, 90], pick = 20;
        for (var i = 0; i < steps.length; i++)
            if (p * 100 >= steps[i]) pick = steps[i];
        return "battery_charging_" + pick;
    }
    if (p >= 0.95) return "battery_full";
    return "battery_" + Math.min(6, Math.floor(p * 7)) + "_bar";
}
