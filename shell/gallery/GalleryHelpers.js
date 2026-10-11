// Pure helpers for the gallery (kept out of QML so delegates do not reach into the root's scope).
.pragma library

// on_primary -> primaryOn, surface_container_low -> surfaceContainerLow (mirrors tools/gen_qml.py qml_name)
function roleProperty(role) {
    var on = role.indexOf("on_") === 0;
    var parts = (on ? role.slice(3) : role).split("_");
    var name = parts[0] + parts.slice(1).map(function (p) { return p[0].toUpperCase() + p.slice(1); }).join("");
    return on ? name + "On" : name;
}

// Relative luminance good enough to pick black or white text for a swatch.
function luminance(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}

// [{kind, size}] for every size of one kind.
function pairs(kind, sizes) {
    return sizes.map(function (sz) { return { kind: kind, size: sz }; });
}

// [{kind, size}] for every button type at one size.
function pairsBySize(size) {
    return ["filled", "tonal", "elevated", "outlined", "text"].map(function (t) { return { kind: t, size: size }; });
}
