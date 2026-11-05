// Clipboard history (D119) as plain functions: cliphist's list and the search over it, so it tests offscreen.
.pragma library

// `cliphist list`'s output, newest first ("<id>\t<preview>" per line), as [{line, id, text, image}]. `line` is what
// cliphist decode and delete take back; an image's preview is "[[ binary data 12 KiB png 100x100 ]]".
function parse(text) {
    var out = [];
    String(text || "").split("\n").forEach(function (line) {
        var tab = line.indexOf("\t");
        if (tab <= 0) return;
        var id = line.substring(0, tab);
        if (!/^\d+$/.test(id)) return;
        var preview = line.substring(tab + 1);
        var image = /^\[\[ binary data .*\]\]$/.test(preview);
        out.push({ line: line, id: id, text: image ? imageLabel(preview) : preview, image: image });
    });
    return out;
}

// "[[ binary data 12 KiB png 100x100 ]]" as "PNG image, 100 × 100, 12 KiB".
function imageLabel(preview) {
    var m = /binary data\s+(\S+ \S+)\s+(\S+)(?:\s+(\d+)x(\d+))?/.exec(preview);
    if (!m) return "Image";
    return m[2].toUpperCase() + " image" + (m[3] ? ", " + m[3] + " × " + m[4] : "") + ", " + m[1];
}

// The entries whose text has every word of `query`, in their order (newest first).
function filter(entries, query) {
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function (w) { return w !== ""; });
    if (words.length === 0) return entries;
    return entries.filter(function (e) {
        var t = e.text.toLowerCase();
        return words.every(function (w) { return t.indexOf(w) >= 0; });
    });
}

// What the shell runs: `line` is passed as an argument, never put in the script.
function copyCommand(line) {
    return ["sh", "-c", 'printf "%s\\n" "$1" | cliphist decode | wl-copy', "sh", line];
}
function deleteCommand(line) {
    return ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "sh", line];
}
