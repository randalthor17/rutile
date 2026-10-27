// File jobs the shell runs through `sh` (D53), so its run-time needs no Python: read several files at once, apply a
// list of changes (write atomically, move, remove, signal a program), and run matugen with a config made here.
// Each is one Process command built from these functions; paths and texts go as arguments, never into the
// script, so nothing in them is ever run. Plain JS, so it tests offscreen.
.pragma library

var MARK = "@@rutile-file:";

// Prints each file as "\n@@rutile-file:<1 or 0>:<path>\n" and its text (1: it exists, 0: it does not). A path given
// as "?<path>" is only checked for existence: its text is "" (it exists) or null, under the key "?<path>".
var READ_SCRIPT = 'for f do\n' +
    '  case "$f" in "?"*) if [ -e "${f#?}" ]; then printf "\\n' + MARK + '1:%s\\n" "$f"; ' +
    'else printf "\\n' + MARK + '0:%s\\n" "$f"; fi; continue;; esac\n' +
    '  if [ -f "$f" ]; then printf "\\n' + MARK + '1:%s\\n" "$f"; cat -- "$f"; ' +
    'else printf "\\n' + MARK + '0:%s\\n" "$f"; fi\n' +
    'done\n';

// Ops in a row: write PATH TEXT MODE | remove PATH | move FROM TO | signal SIG PATTERN. A write goes to a temporary
// file beside the target and is renamed over it, so a reader never sees half a file. It goes on after a failed op
// and exits 1 at the end; a signal no program took is not a failure.
var APPLY_SCRIPT = 'rc=0\n' +
    'while [ $# -gt 0 ]; do\n' +
    '  case "$1" in\n' +
    '  write) mkdir -p -- "$(dirname -- "$2")" && printf "%s" "$3" > "$2.rutile-new" && chmod "$4" "$2.rutile-new" ' +
    '&& mv -f -- "$2.rutile-new" "$2" || rc=1; shift 4;;\n' +
    '  remove) rm -f -- "$2" || rc=1; shift 2;;\n' +
    '  move) mkdir -p -- "$(dirname -- "$3")" && mv -f -- "$2" "$3" || rc=1; shift 3;;\n' +
    '  signal) pkill "-$2" -f "$3"; shift 3;;\n' +
    '  *) echo "unknown op $1" >&2; exit 2;;\n' +
    '  esac\n' +
    'done\n' +
    'exit $rc\n';

// Writes the matugen config into DIR, runs the command after DIR and the config, then prints every output in
// DIR/out as READ_SCRIPT does (named by file name).
var MATUGEN_SCRIPT = 'dir=$1; conf=$2; shift 2\n' +
    'mkdir -p -- "$dir" && rm -rf -- "$dir/out" && printf "%s" "$conf" > "$dir/matugen.toml" || exit 3\n' +
    '"$@" || exit $?\n' +
    'for f in "$dir"/out/*; do [ -f "$f" ] && printf "\\n' + MARK + '1:%s\\n" "${f##*/}" && cat -- "$f"; done\n' +
    'exit 0\n';

function readCommand(paths) {
    return ["sh", "-c", READ_SCRIPT, "sh"].concat(paths);
}

// {path: text, or null when the file does not exist}
function parseRead(out) {
    var files = {};
    var re = /\n@@rutile-file:([01]):([^\n]*)\n/g;
    var marks = [];
    var m;
    while ((m = re.exec(out)) !== null)
        marks.push({ exists: m[1] === "1", name: m[2], start: m.index, end: re.lastIndex });
    for (var i = 0; i < marks.length; i++) {
        var stop = i + 1 < marks.length ? marks[i + 1].start : out.length;
        files[marks[i].name] = marks[i].exists ? out.substring(marks[i].end, stop) : null;
    }
    return files;
}

function applyCommand(ops) {
    var args = ["sh", "-c", APPLY_SCRIPT, "sh"];
    for (var i = 0; i < ops.length; i++) {
        var o = ops[i];
        if (o.op === "write") args.push("write", o.path, o.text, o.mode || "644");
        else if (o.op === "remove") args.push("remove", o.path);
        else if (o.op === "move") args.push("move", o.from, o.to);
        else if (o.op === "signal") args.push("signal", o.sig, o.pattern);
        else throw new Error("unknown op " + o.op);
    }
    return args;
}

// templates: [{name, input}]; outputs land in DIR/out/<name>. Returns the config's text.
function matugenConfig(dir, templates) {
    var lines = ["[config]", "version_check = false", "caching = false"];
    for (var i = 0; i < templates.length; i++) {
        var t = templates[i];
        lines.push("[templates." + t.name.replace(/[^A-Za-z0-9_-]/g, "-") + "]",
                   "input_path = " + JSON.stringify(t.input),
                   "output_path = " + JSON.stringify(dir + "/out/" + t.name));
    }
    return lines.join("\n") + "\n";
}

// source: ["image", path] or ["color", "hex", "#rrggbb"]; extra: further matugen arguments.
function matugenCommand(matugen, dir, templates, source, scheme, mode, contrast, extra) {
    return ["sh", "-c", MATUGEN_SCRIPT, "sh", dir, matugenConfig(dir, templates),
            matugen, "-q", "-c", dir + "/matugen.toml"].concat(source,
            ["-t", scheme, "-m", mode, "--contrast", String(contrast)], extra || []);
}

function dirname(path) {
    var i = path.lastIndexOf("/");
    return i <= 0 ? "/" : path.substring(0, i);
}
