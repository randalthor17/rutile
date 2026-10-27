// Other apps in the shell's colors (D52, preliminary; D53: in the shell, no Python). What each app gets, and the
// plan that makes the switched-on apps wear the palette and takes Rutile's colors back out of the others: plain
// functions of the files' current text, so it tests offscreen. AppColorsService reads the files, renders the
// templates with matugen, and runs the plan's ops (Files.js).
// It changes only what it can undo: its own files, a marked block in a config that includes them, or one key whose
// previous value it keeps and puts back only while the key still holds ours. `done` (kept in state.json) is what
// it did, per app.
.pragma library

var BEGIN = ">>> rutile colors >>>";
var END = "<<< rutile colors <<<";
var ORDER = ["gtk", "qt", "kitty", "ghostty", "btop", "nvim", "firefox"];

// dirs: {config, cache, data, home, theme (the templates' folder), host (tools/pywalfox_host.py)}
function apps(dirs) {
    var c = dirs.config;
    function gtk(v) {
        return { file: c + "/gtk-" + v + ".0/gtk.css", comment: ["/* ", " */"], lines: ["@import 'rutile.css';"],
                 where: "after-imports" };
    }
    function qtKeys(v) {
        return [{ file: c + "/" + v + "/" + v + ".conf", section: "Appearance", key: "color_scheme_path",
                  value: c + "/" + v + "/colors/rutile.conf" },
                { file: c + "/" + v + "/" + v + ".conf", section: "Appearance", key: "custom_palette", value: "true" }];
    }
    return {
        gtk: { title: "GTK 3 and 4",
               files: [["gtk.css", c + "/gtk-3.0/rutile.css"], ["gtk.css", c + "/gtk-4.0/rutile.css"]],
               blocks: [gtk(3), gtk(4)] },
        qt: { title: "Qt (qt5ct, qt6ct)",
              files: [["qtct.conf", c + "/qt5ct/colors/rutile.conf"], ["qtct.conf", c + "/qt6ct/colors/rutile.conf"]],
              keys: qtKeys("qt5ct").concat(qtKeys("qt6ct")) },
        kitty: { title: "kitty", files: [["kitty.conf", c + "/kitty/rutile-colors.conf"]],
                 blocks: [{ file: c + "/kitty/kitty.conf", comment: ["# ", ""], lines: ["include rutile-colors.conf"],
                            where: "end" }],
                 reload: ["USR1", "(^|/)\\.?kitty(-wrapped)?( |$)"] },
        ghostty: { title: "Ghostty", files: [["ghostty", c + "/ghostty/themes/rutile"]],
                   blocks: [{ file: c + "/ghostty/config", comment: ["# ", ""], lines: ["theme = rutile"], where: "end" }],
                   reload: ["USR2", "(^|/)\\.?ghostty(-wrapped)?( |$)"] },
        btop: { title: "btop", files: [["btop.theme", c + "/btop/themes/rutile.theme"]],
                keys: [{ file: c + "/btop/btop.conf", section: null, key: "color_theme", value: '"rutile"' }],
                reload: ["USR2", "(^|/)\\.?btop(-wrapped)?( |$)"] },
        nvim: { title: "Neovim (:colorscheme rutile)", files: [["nvim.lua", c + "/nvim/colors/rutile.lua"]] },
        firefox: { title: "Firefox (Pywalfox)", files: [["pywalfox.conf", dirs.cache + "/rutile/pywalfox.conf"]],
                   firefox: true }
    };
}

function firefoxPaths(dirs) {
    var hosts = dirs.home + "/.mozilla/native-messaging-hosts";
    return { manifest: hosts + "/pywalfox.json", backup: hosts + "/pywalfox.json.rutile-backup",
             host: "?" + dirs.host };            // only whether it is there (the compiled host, D54)
}

// ---- text edits ----

function marker(comment, word) {
    return comment[0] + word + comment[1];
}
function lines(text) {
    if (text === "") return [];
    var rows = text.split("\n");
    if (rows[rows.length - 1] === "") rows.pop();
    return rows;
}
function joined(rows) {
    return rows.length ? rows.join("\n") + "\n" : "";
}

// The text without our marked block (and nothing else).
function stripBlock(text, comment) {
    var out = [];
    var inside = false;
    var rows = (text || "").split("\n");
    for (var i = 0; i < rows.length; i++) {
        if (rows[i] === marker(comment, BEGIN)) { inside = true; continue; }
        if (inside && rows[i] === marker(comment, END)) { inside = false; continue; }
        if (!inside) out.push(rows[i]);
    }
    return out.join("\n");
}

function addBlock(text, comment, blockLines, where) {
    var rows = lines(stripBlock(text || "", comment));
    var block = [marker(comment, BEGIN)].concat(blockLines, [marker(comment, END)]);
    if (where === "after-imports") {
        // CSS: @import comes first; after the others, so ours wins over an earlier theme's
        var i = 0;
        while (i < rows.length && (/^\s*@import/.test(rows[i]) || rows[i].trim() === "")) i++;
        while (i > 0 && rows[i - 1].trim() === "") i--;
        rows.splice.apply(rows, [i, 0].concat(block));
    } else {
        rows = rows.concat(block);
    }
    return joined(rows);
}

// The value of `key` (in [section], or before any section when section is null), or null.
function getKey(text, section, key) {
    var current = null;
    var rows = lines(text || "");
    for (var i = 0; i < rows.length; i++) {
        var s = rows[i].trim();
        if (s[0] === "[" && s[s.length - 1] === "]") { current = s.slice(1, -1); continue; }
        var eq = s.indexOf("=");
        if (current === section && eq > 0 && s.slice(0, eq).trim() === key) return s.slice(eq + 1).trim();
    }
    return null;
}

// `key = value` set, keeping the rest of the text; value null removes the key.
function setKey(text, section, key, value) {
    var entry = section ? key + "=" + value : key + " = " + value;
    var rows = lines(text || "");
    var out = [];
    var current = null;
    var done = false;
    var sectionSeen = false;
    for (var i = 0; i < rows.length; i++) {
        var s = rows[i].trim();
        if (s[0] === "[" && s[s.length - 1] === "]") {
            if (current === section && !done && value !== null) { out.push(entry); done = true; }
            current = s.slice(1, -1);
            if (current === section) sectionSeen = true;
            out.push(rows[i]);
            continue;
        }
        var eq = s.indexOf("=");
        if (current === section && eq > 0 && s.slice(0, eq).trim() === key) {
            if (value !== null && !done) { out.push(entry); done = true; }
            continue;
        }
        out.push(rows[i]);
    }
    if (!done && value !== null) {
        if (section === null) out.unshift(entry);
        else if (sectionSeen) out.push(entry);
        else out = out.concat(out.length ? [""] : [], ["[" + section + "]", entry]);
    }
    return joined(out);
}

// ---- the plan ----

// Every file the plan reads, for these apps (switched on, or themed before).
function paths(dirs, names) {
    var all = apps(dirs);
    var out = [];
    function add(p) { if (out.indexOf(p) < 0) out.push(p); }
    names.forEach(function (n) {
        var a = all[n];
        if (!a) return;
        a.files.forEach(function (f) { add(f[1]); });
        (a.blocks || []).forEach(function (b) { add(b.file); });
        (a.keys || []).forEach(function (k) { add(k.file); });
        if (a.firefox) {
            var fx = firefoxPaths(dirs);
            add(fx.manifest);
            add(fx.backup);
            add(fx.host);
        }
    });
    return out;
}

// The templates to render for the switched-on apps: [{name, input}].
function templates(dirs, wanted) {
    var all = apps(dirs);
    var names = [];
    wanted.forEach(function (n) {
        (all[n] ? all[n].files : []).forEach(function (f) { if (names.indexOf(f[0]) < 0) names.push(f[0]); });
    });
    return names.sort().map(function (n) { return { name: n, input: dirs.theme + "/" + n }; });
}

function firefoxManifest(dirs) {
    return JSON.stringify({ name: "pywalfox", description: "Rutile Shell's colors for Firefox (Pywalfox)",
                            path: dirs.host, type: "stdio",
                            allowed_extensions: ["pywalfox@frewacom.org"] }, null, 2) + "\n";
}

// input: {dirs, wanted: [app], done: {app: record}, files: {path: text|null}, rendered: {template: text}}
// Returns {ops: [Files.js ops], done: the new records, themed: [app], unknown: [app], errors: [text]}. Firefox is left
// out (an error says why) while its host is not built.
function plan(input) {
    var dirs = input.dirs;
    var all = apps(dirs);
    var files = Object.assign({}, input.files);       // the text as the ops leave it
    var done = JSON.parse(JSON.stringify(input.done || {}));
    var ops = [];
    var unknown = input.wanted.filter(function (n) { return !all[n]; });
    if (unknown.length)
        return { ops: [], done: input.done || {}, themed: Object.keys(input.done || {}), unknown: unknown, errors: [] };
    var errors = [];
    var wanted = input.wanted.filter(function (n) {
        if (!all[n].firefox || typeof files[firefoxPaths(dirs).host] === "string") return true;
        errors.push("Firefox: its host " + dirs.host + " is not built (make native)");
        return false;
    });

    function write(path, text, mode) {
        if (files[path] === text) return false;
        files[path] = text;
        ops.push({ op: "write", path: path, text: text, mode: mode || "644" });
        return true;
    }
    function remove(path) {
        if (files[path] === null || files[path] === undefined) return false;
        files[path] = null;
        ops.push({ op: "remove", path: path });
        return true;
    }
    function move(from, to) {
        files[to] = files[from];
        files[from] = null;
        ops.push({ op: "move", from: from, to: to });
    }
    function signal(app) {
        if (all[app].reload) ops.push({ op: "signal", sig: all[app].reload[0], pattern: all[app].reload[1] });
    }

    // apps themed before and no longer wanted: take it back out
    Object.keys(done).sort().forEach(function (app) {
        if (wanted.indexOf(app) >= 0 || (input.wanted.indexOf(app) >= 0 && done[app])) return;   // a skipped app keeps what it has
        var a = all[app] || {};
        var record = done[app];
        var changed = false;
        (record.files || []).forEach(function (f) { changed = remove(f) || changed; });
        (a.blocks || []).forEach(function (b) {
            if (files[b.file] === null || files[b.file] === undefined) return;
            var text = stripBlock(files[b.file], b.comment);
            if (text === files[b.file]) return;
            changed = (text.trim() === "" ? remove(b.file) : write(b.file, text)) || changed;
        });
        Object.keys(record.previous || {}).forEach(function (slot) {
            var parts = slot.split("|");
            var section = parts[1] === "" ? null : parts[1];
            var ours = (a.keys || []).filter(function (k) {
                return k.file === parts[0] && (k.section || "") === parts[1] && k.key === parts[2];
            })[0];
            if (ours && getKey(files[parts[0]], section, parts[2]) === ours.value)   // still ours: put theirs back
                changed = write(parts[0], setKey(files[parts[0]], section, parts[2], record.previous[slot])) || changed;
        });
        if (a.firefox) {
            var fx = firefoxPaths(dirs);
            if (record.backup && files[fx.backup] !== null && files[fx.backup] !== undefined) move(fx.backup, fx.manifest);
            else remove(fx.manifest);
            changed = true;
        }
        delete done[app];
        if (changed) signal(app);
    });

    // apps wanted: wear the colors
    wanted.forEach(function (app) {
        var a = all[app];
        var record = done[app] || (done[app] = {});
        record.files = record.files || [];
        record.previous = record.previous || {};
        var changed = false;
        a.files.forEach(function (f) {
            changed = write(f[1], input.rendered[f[0]]) || changed;
            if (record.files.indexOf(f[1]) < 0) record.files.push(f[1]);
        });
        (a.blocks || []).forEach(function (b) {
            changed = write(b.file, addBlock(files[b.file], b.comment, b.lines, b.where)) || changed;
        });
        (a.keys || []).forEach(function (k) {
            var slot = k.file + "|" + (k.section || "") + "|" + k.key;
            if (!(slot in record.previous)) record.previous[slot] = getKey(files[k.file], k.section, k.key);
            changed = write(k.file, setKey(files[k.file], k.section, k.key, k.value)) || changed;
        });
        if (a.firefox) {
            var fx = firefoxPaths(dirs);
            var manifest = firefoxManifest(dirs);
            var theirs = files[fx.manifest];
            if (theirs !== null && theirs !== undefined && theirs !== manifest && !record.backup) {
                move(fx.manifest, fx.backup);
                record.backup = true;
            }
            write(fx.manifest, manifest);
        }
        if (changed) signal(app);
    });

    var themed = Object.keys(done).sort(function (x, y) { return ORDER.indexOf(x) - ORDER.indexOf(y); });
    return { ops: ops, done: done, themed: themed, unknown: [], errors: errors };
}
