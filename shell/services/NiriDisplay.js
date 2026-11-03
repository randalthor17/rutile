// niri's outputs for the Display page and NiriDisplayService (D69, D74), from `niri msg -j outputs` (one object per output:
// name, make, model, modes [{width, height, refresh_rate (mHz), is_preferred}], current_mode (an index, null when
// off), vrr_supported, vrr_enabled, logical {scale, transform} or null when off). No QML, so it tests alone.
.pragma library

// Its name as people know it: the model, else the make, else the connector.
function title(o) {
    return (o.model || o.make || o.name).trim();
}
function enabled(o) {
    return o.current_mode !== null && o.current_mode !== undefined && !!o.logical;
}
function current(o) {
    return enabled(o) ? o.modes[o.current_mode] ?? null : null;
}
function resolutionLabel(m) {
    return m.width + " × " + m.height;
}
function rateLabel(mhz) {
    const hz = mhz / 1000;
    return (Math.abs(hz - Math.round(hz)) < 0.01 ? Math.round(hz) : hz.toFixed(2)) + " Hz";
}
// what `niri msg output NAME mode` takes
function modeArg(m) {
    return m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3);
}
// The resolutions, largest first, each once.
function resolutions(o) {
    const seen = {};
    const out = [];
    for (const m of o.modes ?? []) {
        const k = m.width + "x" + m.height;
        if (seen[k]) continue;
        seen[k] = true;
        out.push({ width: m.width, height: m.height, label: resolutionLabel(m) });
    }
    return out.sort((a, b) => b.width * b.height - a.width * a.height || b.width - a.width);
}
// The modes at one resolution, fastest first, each rate once.
function rates(o, width, height) {
    const seen = {};
    return (o.modes ?? []).filter(m => m.width === width && m.height === height)
        .sort((a, b) => b.refresh_rate - a.refresh_rate)
        .filter(m => {
            const k = rateLabel(m.refresh_rate);
            if (seen[k]) return false;
            seen[k] = true;
            return true;
        });
}
// The mode to use for a resolution chosen: the preferred one at it, else the current rate's, else the fastest.
function modeFor(o, width, height) {
    const at = (o.modes ?? []).filter(m => m.width === width && m.height === height);
    const cur = current(o);
    return at.find(m => m.is_preferred) ?? (cur ? at.find(m => m.refresh_rate === cur.refresh_rate) : null)
        ?? at.sort((a, b) => b.refresh_rate - a.refresh_rate)[0] ?? null;
}
var SCALES = [1, 1.25, 1.5, 1.75, 2, 2.5, 3];
function scales(o) {
    const s = o.logical?.scale ?? 1;
    return SCALES.indexOf(s) >= 0 ? SCALES : SCALES.concat([s]).sort((a, b) => a - b);
}
function scaleLabel(s) {
    return Math.round(s * 100) + "%";
}
// niri's transforms, counter-clockwise; the flipped ones are left to niri's config
var TRANSFORMS = [["Normal", "normal", "Standard"], ["90", "90", "90°"], ["180", "180", "180°"], ["270", "270", "270°"]];
function transformLabel(t) {
    return (TRANSFORMS.find(x => x[0] === t) ?? [t, t, t])[2];
}
function transformArg(label) {
    return (TRANSFORMS.find(x => x[2] === label) ?? [])[1] ?? "normal";
}
// How many outputs are on: the last one cannot be turned off from here.
function enabledCount(outputs) {
    return outputs.filter(enabled).length;
}
// What the shell keeps of an output the Display page changed (D74): {on, mode (modeArg), scale, transform
// (niri's config spelling), vrr}, from niri's JSON.
function entry(o) {
    if (!enabled(o)) return { on: false };
    const t = (TRANSFORMS.find(x => x[0] === o.logical.transform) ?? [])[1]
        ?? String(o.logical.transform).replace(/^Flipped(\d+)$/, "flipped-$1").toLowerCase();
    return { on: true, mode: modeArg(current(o)), scale: o.logical.scale, transform: t, vrr: !!o.vrr_enabled };
}
// Its `niri msg output NAME ...` commands, in order, each an argument list after the name.
function commands(e) {
    if (!e.on) return [["off"]];
    return [["on"], ["mode", e.mode], ["scale", String(e.scale)], ["transform", e.transform], ["vrr", e.vrr ? "on" : "off"]];
}
// rutile-display.kdl from the kept entries ({name: entry}); "" when there are none.
function entriesKdl(entries) {
    const names = Object.keys(entries ?? {}).sort();
    if (names.length === 0) return "";
    return "// Written by Rutile Shell from Settings > Display; niri reads it through rutile.kdl.\n" + names.map(n => {
        const e = entries[n];
        if (!e.on) return 'output "' + n + '" {\n    off\n}\n';
        const lines = ['output "' + n + '" {', '    mode "' + e.mode + '"', "    scale " + e.scale];
        if (e.transform !== "normal") lines.push('    transform "' + e.transform + '"');
        if (e.vrr) lines.push("    variable-refresh-rate");
        return lines.join("\n") + "\n}\n";
    }).join("");
}
