// The launcher's file search (D133): files and folders in the home folder whose names hold what was typed, found
// with find (five levels down; hidden folders, node_modules and build folders left out) a moment after typing
// stops. Plain functions, so the offscreen tests check them; LauncherWindow.qml runs the command.
.pragma library

var minLength = 3;          // shorter queries search no files
var shown = 8;              // at most this many in the results

// The search's find command for `query` under `home`, at most `limit` hits: "<type> <path below home>" lines. The
// query is an argument with find's wildcards escaped, never part of the script.
function command(home, query, limit) {
    var pattern = "*" + String(query).trim().replace(/[\\*?\[\]]/g, "\\$&") + "*";
    return ["sh", "-c", 'cd -- "$1" && find . -mindepth 1 -maxdepth 5 \\( -name ".*" -o -name node_modules '
            + '-o -name __pycache__ -o -name target -o -name result \\) -prune -o -iname "$2" -printf "%y %P\\n" '
            + '2>/dev/null | head -n "$3"', "sh", home, pattern, String(limit || 200)];
}

// Whether `query` searches files: long enough, and no sum, conversion or emoji.
function wanted(query) {
    var q = String(query || "").trim();
    return q.length >= minLength && q.charAt(0) !== ":";
}

function symbolFor(name, folder) {
    if (folder) return "folder";
    var ext = (/\.([A-Za-z0-9]+)$/.exec(name) || ["", ""])[1].toLowerCase();
    if (/^(png|jpe?g|gif|webp|svg|bmp|heic|avif)$/.test(ext)) return "image";
    if (/^(mp4|mkv|webm|mov|avi)$/.test(ext)) return "movie";
    if (/^(mp3|flac|ogg|opus|wav|m4a)$/.test(ext)) return "music_note";
    if (/^(pdf)$/.test(ext)) return "picture_as_pdf";
    if (/^(zip|tar|gz|xz|zst|7z|rar)$/.test(ext)) return "folder_zip";
    if (/^(js|ts|py|qml|c|h|cpp|rs|go|nix|sh|java|kt|json|toml|yaml|yml)$/.test(ext)) return "code";
    return "description";
}

// The command's output as launcher items for `query`: names holding the query (an older search's hits that no
// longer match are dropped), names starting with it first, then the shallower; at most `shown`.
function parse(text, home, query) {
    var q = String(query || "").trim().toLowerCase();
    var out = [];
    String(text || "").split("\n").forEach(function (line) {
        var m = /^([a-z]) (.+)$/.exec(line);
        if (!m) return;
        var rel = m[2];
        var name = rel.split("/").pop();
        if (q === "" || name.toLowerCase().indexOf(q) < 0) return;
        var dir = rel.indexOf("/") >= 0 ? rel.slice(0, rel.lastIndexOf("/")) : "";
        out.push({ type: "file", id: "file:" + rel, name: name, subtitle: "~/" + dir + (dir ? "/" : ""),
                   symbol: symbolFor(name, m[1] === "d"), path: home.replace(/\/+$/, "") + "/" + rel,
                   starts: name.toLowerCase().indexOf(q) === 0, depth: rel.split("/").length });
    });
    out.sort(function (a, b) {
        if (a.starts !== b.starts) return a.starts ? -1 : 1;
        if (a.depth !== b.depth) return a.depth - b.depth;
        return a.name.localeCompare(b.name);
    });
    return out.slice(0, shown);
}

// Opens a found file or folder in its app.
function openCommand(path) {
    return ["gio", "open", path];
}
