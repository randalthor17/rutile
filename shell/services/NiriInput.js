// niri's input section from the shell's input settings (Settings > Input, D70), for rutile-input.kdl, which the
// home-manager module includes after niri's own config: included sections merge, so each value here wins.
// niri cannot turn a flag off from an included file (`tap false` does not parse), so a flag is written only when
// on. No QML, so it tests alone.
.pragma library

function num(v) {
    // KDL wants a decimal point on a fraction, and none needed on a whole number
    return String(Math.round(v * 100) / 100);
}

// `s`: {repeatDelay, repeatRate, touchpadTap, touchpadNaturalScroll, touchpadSpeed, mouseNaturalScroll,
// mouseSpeed, mouseFlat}
function kdl(s) {
    const touchpad = [];
    if (s.touchpadTap) touchpad.push("tap");
    if (s.touchpadNaturalScroll) touchpad.push("natural-scroll");
    touchpad.push("accel-speed " + num(s.touchpadSpeed));
    const mouse = [];
    if (s.mouseNaturalScroll) mouse.push("natural-scroll");
    mouse.push("accel-speed " + num(s.mouseSpeed));
    mouse.push('accel-profile "' + (s.mouseFlat ? "flat" : "adaptive") + '"');
    const block = (name, lines) => "    " + name + " {\n" + lines.map(l => "        " + l + "\n").join("") + "    }\n";
    return "// Written by Rutile Shell from Settings > Input; niri includes it after its own config.\n" +
        "input {\n" +
        block("keyboard", ["repeat-delay " + Math.round(s.repeatDelay), "repeat-rate " + Math.round(s.repeatRate)]) +
        block("touchpad", touchpad) +
        block("mouse", mouse) +
        "}\n";
}
