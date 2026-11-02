// The Display page's choices, from niri's outputs as `niri msg -j outputs` gives them (one object per output:
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
// The output's settings as niri's config has them, to keep them (`niri msg output` lasts until niri restarts).
function kdl(o) {
    if (!enabled(o)) return 'output "' + o.name + '" {\n    off\n}\n';
    const m = current(o);
    const lines = ['output "' + o.name + '" {', '    mode "' + modeArg(m) + '"', '    scale ' + o.logical.scale];
    // niri's JSON says Flipped90 where its config says flipped-90
    const t = (TRANSFORMS.find(x => x[0] === o.logical.transform) ?? [])[1]
        ?? String(o.logical.transform).replace(/^Flipped(\d+)$/, "flipped-$1").toLowerCase();
    if (t !== "normal") lines.push('    transform "' + t + '"');
    if (o.vrr_enabled) lines.push("    variable-refresh-rate");
    return lines.join("\n") + "\n}\n";
}
