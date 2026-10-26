// brightnessctl's machine-readable output and commands, kept apart from BrightnessService.qml so the
// offscreen QML tests can check them without Quickshell. Line format (brightnessctl 0.5):
// "device,class,current,percent,max", e.g. "intel_backlight,backlight,512,48%,1060".
.pragma library

// The first backlight line of `brightnessctl -m -c backlight info`, or null.
function parse(text) {
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].trim().split(",");
        if (f.length !== 5 || f[1] !== "backlight") continue;
        var current = parseInt(f[2], 10), max = parseInt(f[4], 10);
        if (!(max > 0) || !(current >= 0)) continue;
        return { device: f[0], current: current, max: max };
    }
    return null;
}

// The raw value for a fraction; never 0, which on many panels turns the backlight off.
function rawFor(fraction, max) {
    return Math.max(1, Math.min(max, Math.round(fraction * max)));
}

function readCommand() {
    return ["brightnessctl", "-m", "-c", "backlight", "info"];
}

function setCommand(device, raw) {
    return ["brightnessctl", "-m", "-c", "backlight", "-d", device, "set", String(raw)];
}
