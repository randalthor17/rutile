// The shell's settings that niri takes (D70, D74), as rutile-settings.kdl, which niri reads through rutile.kdl,
// included at the end of niri's own config: included sections merge, so each value here wins over the user's.
// Each part has its own switch and is written only while on: input (Settings > Keyboard, mouse & touchpad) and
// animations (niri's following the shell's animation speed, Settings > Accessibility). niri 26.04 merges an
// included touchpad, mouse or xkb section by replacing the user's whole (merge_clone!), so a flag left out here
// is off whatever the user's config says; animations take `on`, which undoes the user's `off`. No QML, so it
// tests alone.
.pragma library

function num(v) {
    // two decimals at most; niri takes "0" and "0.5" alike
    return String(Math.round(v * 100) / 100);
}

function block(name, lines, indent) {
    const pad = " ".repeat(indent);
    return pad + name + " {\n" + lines.map(l => pad + "    " + l + "\n").join("") + pad + "}\n";
}

// niri's input section. `s`: {keyboardLayout ("" leaves niri's), repeatDelay, repeatRate, touchpadTap,
// touchpadDisableWhileTyping, touchpadNaturalScroll, touchpadSpeed, mouseNaturalScroll, mouseSpeed, mouseFlat}
function input(s) {
    const touchpad = [];
    if (s.touchpadTap) touchpad.push("tap");
    if (s.touchpadDisableWhileTyping) touchpad.push("dwt");
    if (s.touchpadNaturalScroll) touchpad.push("natural-scroll");
    touchpad.push("accel-speed " + num(s.touchpadSpeed));
    const mouse = [];
    if (s.mouseNaturalScroll) mouse.push("natural-scroll");
    mouse.push("accel-speed " + num(s.mouseSpeed));
    mouse.push('accel-profile "' + (s.mouseFlat ? "flat" : "adaptive") + '"');
    const keyboard = ["repeat-delay " + Math.round(s.repeatDelay), "repeat-rate " + Math.round(s.repeatRate)];
    let kb = block("keyboard", keyboard, 4);
    if (s.keyboardLayout) {
        // xkb inside keyboard: written by hand to keep the nesting readable
        kb = kb.replace(/    }\n$/, "        xkb {\n            layout \"" + s.keyboardLayout + "\"\n        }\n    }\n");
    }
    return "input {\n" + kb + block("touchpad", touchpad, 4) + block("mouse", mouse, 4) + "}\n";
}

// niri's animations at the shell's speed (Motion.speed: 1 as made, 2 twice as fast, 0 none): niri's slowdown is
// the inverse, and `on` undoes an `off` in the user's config.
function animations(speed) {
    if (!(speed > 0)) return "animations {\n    off\n}\n";
    return "animations {\n    on\n    slowdown " + num(1 / speed) + "\n}\n";
}

// The whole file: `parts` {input: s or null, animations: speed or null}; "" when no part is on (the file goes).
function kdl(parts) {
    const out = [];
    if (parts.input) out.push(input(parts.input));
    if (parts.animations !== null && parts.animations !== undefined) out.push(animations(parts.animations));
    if (out.length === 0) return "";
    return "// Written by Rutile Shell from its settings; niri reads it through rutile.kdl, after its own config.\n" +
        out.join("");
}
