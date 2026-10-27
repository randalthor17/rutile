// palette.json (format 1), the shell's only color input (D53): its check, the same as tools/palette.py's
// `validate`, so the shell can render it from the wallpaper itself (WallpaperService runs matugen) and never puts
// a broken palette in place.
.pragma library

var HEX = /^#[0-9a-f]{6}$/;
var SCHEMES = ["scheme-content", "scheme-expressive", "scheme-fidelity", "scheme-fruit-salad", "scheme-monochrome",
               "scheme-neutral", "scheme-rainbow", "scheme-tonal-spot", "scheme-vibrant"];

// The problems with `doc` (none: it is valid). `roles`: the role names every mode must have (theme/roles.json).
function validate(doc, roles) {
    var errs = [];
    if (doc === null || typeof doc !== "object" || Array.isArray(doc)) return ["palette is not an object"];
    if (doc.format !== 1) errs.push("format must be 1, got " + JSON.stringify(doc.format));
    if (doc.mode !== "dark" && doc.mode !== "light") errs.push("mode must be dark or light, got " + JSON.stringify(doc.mode));
    if (!HEX.test(String(doc.source_color))) errs.push("bad source_color " + JSON.stringify(doc.source_color));
    var colors = doc.colors;
    var keys = colors && typeof colors === "object" ? Object.keys(colors).sort() : [];
    if (keys.join() !== "dark,light") return errs.concat(["colors must have exactly the keys dark and light"]);
    var want = {};
    for (var r = 0; r < roles.length; r++) want[roles[r]] = true;
    ["dark", "light"].forEach(function (mode) {
        var table = colors[mode];
        if (table === null || typeof table !== "object") {
            errs.push("colors." + mode + " is not an object");
            return;
        }
        var missing = roles.filter(function (role) { return !(role in table); });
        if (missing.length) errs.push("colors." + mode + " missing roles: " + missing.join(", "));
        Object.keys(table).forEach(function (role) {
            if (role === "source_color") return;
            if (!want[role]) errs.push("colors." + mode + " has unexpected role " + JSON.stringify(role));
            if (!HEX.test(String(table[role]))) errs.push("colors." + mode + "." + role + " is not #rrggbb: " + JSON.stringify(table[role]));
        });
    });
    return errs;
}

// The palette as written: the rendered document, and how it was made, so other apps can be given the same colors
// (D52). Text ends with a newline, like palette.py's.
function finish(doc, scheme, contrast) {
    var out = JSON.parse(JSON.stringify(doc));
    out.scheme = scheme;
    out.contrast = contrast;
    return JSON.stringify(out, null, 2) + "\n";
}
