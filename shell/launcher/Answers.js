// The launcher's answers (D130): a sum worked out ("2+3*4", "sqrt(2)", "15% * 80"), a unit converted ("5 km to mi",
// "100 f in c", "2 GiB to MB"), and emoji found by name (":smile"). Plain functions, so the offscreen tests check
// them. A sum is read by a small parser of its own: nothing typed is ever run as code.
.pragma library

// ---- sums ----

var FUNCTIONS = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
    ln: Math.log, log: Math.log10, log2: Math.log2, exp: Math.exp,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan
};
var CONSTANTS = { pi: Math.PI, "π": Math.PI, e: Math.E, tau: 2 * Math.PI };

function tokens(text) {
    var out = [];
    var s = String(text).replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/,/g, "");
    var i = 0;
    while (i < s.length) {
        var c = s[i];
        if (/\s/.test(c)) { i++; continue; }
        var num = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(s.slice(i));
        if (num) { out.push({ t: "num", v: parseFloat(num[0]) }); i += num[0].length; continue; }
        var id = /^([a-z]+[0-9]?|π)/i.exec(s.slice(i));
        if (id) { out.push({ t: "id", v: id[0].toLowerCase() }); i += id[0].length; continue; }
        if ("+-*/^%()".indexOf(c) >= 0) {
            if (c === "*" && s[i + 1] === "*") { out.push({ t: "op", v: "^" }); i += 2; continue; }
            out.push({ t: "op", v: c });
            i++;
            continue;
        }
        return null;
    }
    return out;
}

// The value of `text` as a sum, or null when it is none (or not a finite number).
function evaluate(text) {
    var ts = tokens(text);
    if (!ts || ts.length === 0) return null;
    var p = 0;
    function peek(v) { return p < ts.length && ts[p].t === "op" && ts[p].v === v; }
    function expr() {
        var v = term();
        while (peek("+") || peek("-")) {
            var op = ts[p++].v;
            var r = term();
            v = op === "+" ? v + r : v - r;
        }
        return v;
    }
    function term() {
        var v = unary();
        for (;;) {
            if (peek("*")) { p++; v *= unary(); }
            else if (peek("/")) { p++; v /= unary(); }
            else if (peek("%") && p + 1 < ts.length && !(ts[p + 1].t === "op" && ts[p + 1].v !== "(")) {
                p++;
                v %= unary();       // "7 % 3": the remainder
            }
            else return v;
        }
    }
    function unary() {
        if (peek("-")) { p++; return -unary(); }
        if (peek("+")) { p++; return unary(); }
        return power();
    }
    function power() {
        var v = postfix();
        if (peek("^")) { p++; return Math.pow(v, unary()); }
        return v;
    }
    function postfix() {
        var v = primary();
        // "15%" at the end or before an operator: a hundredth
        while (peek("%") && (p + 1 >= ts.length || (ts[p + 1].t === "op" && ts[p + 1].v !== "("))) {
            p++;
            v /= 100;
        }
        return v;
    }
    function primary() {
        if (p >= ts.length) throw "end";
        var tk = ts[p++];
        if (tk.t === "num") return tk.v;
        if (tk.t === "op" && tk.v === "(") {
            var v = expr();
            if (!peek(")")) throw "paren";
            p++;
            return v;
        }
        if (tk.t === "id") {
            if (CONSTANTS[tk.v] !== undefined) return CONSTANTS[tk.v];
            if (FUNCTIONS[tk.v] && peek("(")) {
                p++;
                var a = expr();
                if (!peek(")")) throw "paren";
                p++;
                return FUNCTIONS[tk.v](a);
            }
        }
        throw "unexpected";
    }
    try {
        var v = expr();
        if (p !== ts.length || !isFinite(v)) return null;
        return v;
    } catch (e) {
        return null;
    }
}

// A number as the answer shows it: at most 12 significant digits, no trailing zeros.
function format(v) {
    if (Math.abs(v) < 1e-12) return "0";
    var s = String(Number(v.toPrecision(12)));
    return s;
}

// A sum's answer item, or null: only text with an operator, a function or a constant, so a plain number or an
// app's name is no sum.
function sum(query) {
    var q = String(query).trim();
    if (!/[+\-*/^%×÷()]|[a-z]\(|\bpi\b|π/i.test(q) || /^[+-]?\d*\.?\d+$/.test(q)) return null;
    var v = evaluate(q);
    if (v === null) return null;
    var text = format(v);
    return { type: "answer", id: "answer", name: "= " + text, subtitle: q + " · Enter copies", symbol: "calculate",
             copy: text };
}

// ---- units ----

// Each unit's kind and size in that kind's base (meters, kilograms, liters, seconds, bytes, m/s); temperatures
// are converted on their own.
var UNITS = {};
function unit(kind, size, names) {
    names.forEach(function (n) { UNITS[n] = { kind: kind, size: size, name: names[0] }; });
}
unit("length", 1, ["m", "meter", "meters", "metre", "metres"]);
unit("length", 1000, ["km", "kilometer", "kilometers", "kilometre", "kilometres"]);
unit("length", 0.01, ["cm", "centimeter", "centimeters", "centimetre", "centimetres"]);
unit("length", 0.001, ["mm", "millimeter", "millimeters", "millimetre", "millimetres"]);
unit("length", 1609.344, ["mi", "mile", "miles"]);
unit("length", 0.9144, ["yd", "yard", "yards"]);
unit("length", 0.3048, ["ft", "foot", "feet"]);
unit("length", 0.0254, ["in", "inch", "inches"]);
unit("length", 1852, ["nmi", "nautical mile", "nautical miles"]);
unit("mass", 1, ["kg", "kilogram", "kilograms", "kilo", "kilos"]);
unit("mass", 0.001, ["g", "gram", "grams"]);
unit("mass", 1e-6, ["mg", "milligram", "milligrams"]);
unit("mass", 1000, ["t", "tonne", "tonnes"]);
unit("mass", 0.45359237, ["lb", "lbs", "pound", "pounds"]);
unit("mass", 0.028349523125, ["oz", "ounce", "ounces"]);
unit("mass", 6.35029318, ["st", "stone", "stones"]);
unit("volume", 1, ["l", "liter", "liters", "litre", "litres"]);
unit("volume", 0.001, ["ml", "milliliter", "milliliters", "millilitre", "millilitres"]);
unit("volume", 1000, ["m3", "m³", "cubic meter", "cubic meters"]);
unit("volume", 3.785411784, ["gal", "gallon", "gallons"]);
unit("volume", 0.946352946, ["qt", "quart", "quarts"]);
unit("volume", 0.473176473, ["pt", "pint", "pints"]);
unit("volume", 0.2365882365, ["cup", "cups"]);
unit("volume", 0.0295735295625, ["floz", "fl oz", "fluid ounce", "fluid ounces"]);
unit("time", 1, ["s", "sec", "secs", "second", "seconds"]);
unit("time", 0.001, ["ms", "millisecond", "milliseconds"]);
unit("time", 60, ["min", "mins", "minute", "minutes"]);
unit("time", 3600, ["h", "hr", "hrs", "hour", "hours"]);
unit("time", 86400, ["d", "day", "days"]);
unit("time", 604800, ["wk", "week", "weeks"]);
unit("time", 31557600, ["yr", "year", "years"]);
unit("data", 1, ["B", "byte", "bytes"]);
unit("data", 0.125, ["bit", "bits"]);
unit("data", 1e3, ["KB", "kB", "kilobyte", "kilobytes"]);
unit("data", 1e6, ["MB", "megabyte", "megabytes"]);
unit("data", 1e9, ["GB", "gigabyte", "gigabytes"]);
unit("data", 1e12, ["TB", "terabyte", "terabytes"]);
unit("data", 1024, ["KiB", "kibibyte", "kibibytes"]);
unit("data", 1048576, ["MiB", "mebibyte", "mebibytes"]);
unit("data", 1073741824, ["GiB", "gibibyte", "gibibytes"]);
unit("data", 1099511627776, ["TiB", "tebibyte", "tebibytes"]);
unit("speed", 1, ["m/s", "mps"]);
unit("speed", 1 / 3.6, ["km/h", "kmh", "kph"]);
unit("speed", 0.44704, ["mph"]);
unit("speed", 0.514444, ["kn", "knot", "knots"]);
unit("temperature", 0, ["c", "°c", "celsius"]);
unit("temperature", 0, ["f", "°f", "fahrenheit"]);
unit("temperature", 0, ["k", "kelvin"]);

// A unit by what was typed, in any case ("mb" is MB: no two units here differ only by case).
function findUnit(text) {
    var t = String(text).trim();
    var lower = t.toLowerCase();
    for (var k in UNITS) if (k.toLowerCase() === lower) return UNITS[k];
    return null;
}

function toKelvin(v, name) {
    return name === "c" ? v + 273.15 : name === "f" ? (v - 32) * 5 / 9 + 273.15 : v;
}
function fromKelvin(v, name) {
    return name === "c" ? v - 273.15 : name === "f" ? (v - 273.15) * 9 / 5 + 32 : v;
}

// "<number> <unit> to|in <unit>": the converted value as an answer item, or null.
function convert(query) {
    var m = /^\s*([-+]?(?:\d[\d,]*\.?\d*|\.\d+))\s*(.+?)\s+(?:to|in|as|into)\s+(.+?)\s*$/i.exec(String(query));
    if (!m) return null;
    var from = findUnit(m[2]), to = findUnit(m[3]);
    if (!from || !to || from.kind !== to.kind) return null;
    var v = parseFloat(m[1].replace(/,/g, ""));
    var out = from.kind === "temperature" ? fromKelvin(toKelvin(v, from.name), to.name) : v * from.size / to.size;
    if (!isFinite(out)) return null;
    var label = to.kind === "temperature" ? (to.name === "k" ? " K" : " °" + to.name.toUpperCase()) : " " + to.name;
    var text = format(out);
    return { type: "answer", id: "answer", name: text + label, subtitle: m[1] + " " + m[2] + " · Enter copies",
             symbol: "straighten", copy: text };
}

// The answer to `query`, if it is a sum or a conversion; else null.
function answer(query) {
    return convert(query) || sum(query);
}

// ---- emoji ----

// Unicode's emoji-test.txt as [{emoji, name, words}]: fully-qualified ones only, skin-tone variants left out (the
// plain one stands for them); `words` adds the subgroup ("face-smiling") for search.
function parseEmoji(text) {
    var out = [];
    var subgroup = "";
    String(text || "").split("\n").forEach(function (line) {
        var sg = /^# subgroup: (.*)$/.exec(line);
        if (sg) { subgroup = sg[1].replace(/-/g, " "); return; }
        var m = /; fully-qualified\s+# (\S+) E\d+\.\d+ (.+)$/.exec(line);
        if (!m || /skin tone/.test(m[2])) return;
        out.push({ emoji: m[1], name: m[2], words: m[2] + " " + subgroup });
    });
    return out;
}

// `list`'s emoji for `query` (what follows the colon), as launcher items: names that start with it first, then
// names with a word starting with it, then the rest that mention it; at most `limit`.
function emojiResults(list, query, limit) {
    var q = String(query || "").trim().toLowerCase();
    if (q === "") return [];
    var first = [], word = [], rest = [];
    for (var i = 0; i < list.length; i++) {
        var e = list[i];
        var name = e.name.toLowerCase();
        if (name.indexOf(q) === 0) first.push(e);
        else if ((" " + name).indexOf(" " + q) >= 0) word.push(e);
        else if ((" " + e.words.toLowerCase()).indexOf(" " + q) >= 0 || name.indexOf(q) >= 0) rest.push(e);
    }
    return first.concat(word, rest).slice(0, limit || 50).map(function (e) {
        return { type: "emoji", id: "emoji:" + e.emoji, name: e.name, glyph: e.emoji, subtitle: "Enter copies",
                 copy: e.emoji };
    });
}
