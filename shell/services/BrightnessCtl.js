// The displays' brightness tools, their machine-readable output and commands, kept apart from
// BrightnessService.qml so the offscreen QML tests can check them without Quickshell.
// brightnessctl (D39) sets backlights (laptop panels). Line format (brightnessctl 0.5):
// "device,class,current,percent,max", e.g. "intel_backlight,backlight,512,48%,1060".
// ddcutil (D113) sets external monitors over DDC/CI (VCP feature 0x10, brightness), by I2C bus.
.pragma library

// Every backlight line of `brightnessctl -m -l -c backlight`: [{device, current, max}].
function parseAll(text) {
    var out = [];
    String(text || "").split("\n").forEach(function (line) {
        var f = line.trim().split(",");
        if (f.length !== 5 || f[1] !== "backlight") return;
        var current = parseInt(f[2], 10), max = parseInt(f[4], 10);
        if (!(max > 0) || !(current >= 0)) return;
        out.push({ device: f[0], current: current, max: max });
    });
    return out;
}

// The raw value for a fraction. A backlight never gets 0 (`floor` 1), which on many panels turns it
// off; a monitor's 0 is only its dimmest.
function rawFor(fraction, max, floor) {
    var low = floor === undefined ? 1 : floor;
    return Math.max(low, Math.min(max, Math.round(fraction * max)));
}

function readCommand() {
    return ["brightnessctl", "-m", "-l", "-c", "backlight"];
}

function setCommand(device, raw) {
    return ["brightnessctl", "-m", "-c", "backlight", "-d", device, "set", String(raw)];
}

// `ddcutil detect --terse`: the monitors that answer DDC/CI ("Display N" blocks; "Invalid display"
// ones do not), as [{bus, output, model}]. `output` is the DRM connector without its card ("DP-1"),
// as niri names outputs.
function parseDetect(text) {
    var out = [];
    var current = null;
    String(text || "").split("\n").forEach(function (line) {
        if (/^\S/.test(line)) {
            current = /^Display \d+/.test(line) ? { bus: -1, output: "", model: "" } : null;
            if (current) out.push(current);
            return;
        }
        if (!current) return;
        var m = /^\s*I2C bus:\s*\/dev\/i2c-(\d+)/.exec(line);
        if (m) current.bus = parseInt(m[1], 10);
        m = /^\s*DRM connector:\s*(\S+)/.exec(line);
        if (m) current.output = m[1].replace(/^card\d+-/, "");
        m = /^\s*Monitor:\s*(.*)$/.exec(line);
        if (m) current.model = (m[1].split(":")[1] || "").trim();
    });
    return out.filter(function (d) { return d.bus >= 0; });
}

function detectCommand() {
    return ["ddcutil", "detect", "--terse"];
}

// Reads every bus's brightness in one process; each line is "BUS " and ddcutil's brief answer.
function ddcReadCommand(buses) {
    return ["sh", "-c", 'for b; do printf "%s " "$b"; ddcutil getvcp 10 --brief --bus "$b" 2>/dev/null || echo; done',
            "sh"].concat(buses.map(String));
}

// ddcReadCommand's output: {bus: {current, max}} for each bus that answered ("8 VCP 10 C 70 100").
function parseVcp(text) {
    var out = {};
    String(text || "").split("\n").forEach(function (line) {
        var m = /^(\d+) VCP 10 C (\d+) (\d+)\s*$/.exec(line.trim());
        if (m && parseInt(m[3], 10) > 0)
            out[m[1]] = { current: parseInt(m[2], 10), max: parseInt(m[3], 10) };
    });
    return out;
}

function ddcSetCommand(bus, raw) {
    return ["ddcutil", "setvcp", "10", String(raw), "--bus", String(bus), "--noverify"];
}

// The displays whose brightness can be set, backlights first: [{id, kind, device, output, name, max,
// value}]. A monitor that did not answer a read is left out.
function displays(backlights, monitors, vcp) {
    var out = backlights.map(function (b) {
        return { id: "backlight:" + b.device, kind: "backlight", device: b.device, output: "",
                 name: "Built-in display", max: b.max, value: b.current / b.max };
    });
    monitors.forEach(function (m) {
        var v = vcp[String(m.bus)];
        if (!v) return;
        out.push({ id: "ddc:" + m.bus, kind: "ddc", device: String(m.bus), output: m.output,
                   name: m.model || m.output || "Display", max: v.max, value: v.current / v.max });
    });
    return out;
}

// The display that is niri's output `name`: a monitor by its connector, or a backlight for a built-in
// panel (eDP, LVDS, DSI); null when none can be set.
function forOutput(list, name) {
    var all = list || [];
    var ddc = all.filter(function (d) { return d.kind === "ddc" && d.output === name; })[0];
    if (ddc) return ddc;
    if (/^(eDP|LVDS|DSI)-/.test(String(name)))
        return all.filter(function (d) { return d.kind === "backlight"; })[0] || null;
    return null;
}

function command(display, raw) {
    return display.kind === "ddc" ? ddcSetCommand(display.device, raw) : setCommand(display.device, raw);
}
