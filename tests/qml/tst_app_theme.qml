import QtQuick
import QtTest
import "../qs/services/AppTheme.js" as AppTheme
import "../qs/services/Files.js" as Files
import "../qs/services/Palette.js" as Palette

// The JS that replaced tools/apptheme.py and the shell's use of tools/palette.py (D53): the app theming plan from
// the files' text, the file-job commands and their output, the palette check. The same cases the Python had; the
// files themselves are exercised in tests/qs/tst_app_colors.qml (a sandbox HOME, real matugen).
TestCase {
    name: "AppTheme"

    readonly property var dirs: ({ config: "/h/.config", cache: "/h/.cache", data: "/h/.local/share", home: "/h",
                                   theme: "/r/theme/apps", host: "/r/tools/pywalfox_host.py" })
    readonly property var rendered: ({ "gtk.css": "@define-color accent_bg_color #aabbcc;\n", "kitty.conf": "cursor #aabbcc\n",
                                       "btop.theme": "theme[main_bg]=\"#000000\"\n", "qtct.conf": "[ColorScheme]\n",
                                       "ghostty": "background = #111111\n", "nvim.lua": "-- rutile\n",
                                       "pywalfox.json": "{}\n" })

    // Runs the plan's ops on a map of files, as the sh script would.
    function run(files, ops) {
        const out = Object.assign({}, files);
        for (const o of ops) {
            if (o.op === "write") out[o.path] = o.text;
            else if (o.op === "remove") out[o.path] = null;
            else if (o.op === "move") { out[o.to] = out[o.from]; out[o.from] = null; }
        }
        return out;
    }
    // One sync: plan from the files, then apply. Returns {files, done, ops}.
    function sync(files, wanted, done) {
        const p = AppTheme.plan({ dirs: dirs, wanted: wanted, done: done ?? {}, files: files, rendered: rendered });
        return { files: run(files, p.ops), done: p.done, ops: p.ops, themed: p.themed, unknown: p.unknown };
    }
    function count(text, part) { return text.split(part).length - 1; }

    function test_nothing_wanted_nothing_done() {
        const r = sync({}, []);
        compare(r.ops.length, 0);
        compare(Object.keys(r.done).length, 0);
    }

    function test_gtk_after_other_imports_and_undone_exactly() {
        const original = "@import 'noctalia.css';\n\nwindow { margin: 0; }\n";
        const css3 = "/h/.config/gtk-3.0/gtk.css", css4 = "/h/.config/gtk-4.0/gtk.css";
        let r = sync({ [css3]: original, [css4]: null }, ["gtk"]);
        const rows = r.files[css3].split("\n");
        compare(rows[0], "@import 'noctalia.css';", "theirs stays first");
        compare(rows.slice(1, 4).join("|"), "/* >>> rutile colors >>> */|@import 'rutile.css';|/* <<< rutile colors <<< */",
                "ours after it, before any rule, so ours wins");
        verify(r.files[css3].indexOf("window { margin: 0; }") > 0);
        compare(r.files["/h/.config/gtk-3.0/rutile.css"], rendered["gtk.css"]);
        compare(r.files[css4].split("\n")[1], "@import 'rutile.css';", "made when missing");
        const again = sync(r.files, ["gtk"], r.done);
        compare(again.ops.length, 0, "a second sync writes nothing");
        const off = sync(r.files, [], r.done);
        compare(off.files[css3], original, "turned off: exactly as it was");
        compare(off.files["/h/.config/gtk-3.0/rutile.css"], null);
        compare(off.files[css4], null, "the gtk.css it made, holding only its block, goes");
        compare(Object.keys(off.done).length, 0);
    }

    function test_kitty_block_at_the_end_and_reload() {
        const conf = "/h/.config/kitty/kitty.conf";
        const original = "font_size 12\ninclude theme.conf\n";
        let r = sync({ [conf]: original }, ["kitty"]);
        verify(r.files[conf].startsWith(original));
        verify(r.files[conf].endsWith("include rutile-colors.conf\n# <<< rutile colors <<<\n"));
        const signals = r.ops.filter(o => o.op === "signal");
        compare(signals.length, 1);
        compare(signals[0].sig, "USR1", "kitty reloads on SIGUSR1");
        compare(sync(r.files, ["kitty"], r.done).ops.length, 0, "nothing changed: no write, no signal");
        const off = sync(r.files, [], r.done);
        compare(off.files[conf], original);
        compare(off.ops.filter(o => o.op === "signal").length, 1, "turned off: it reloads its own colors");
    }

    function test_btop_key_comes_back_unless_changed_since() {
        const conf = "/h/.config/btop/btop.conf";
        const original = '#? Config file for btop\ncolor_theme = "Default"\nupdate_ms = 2000\n';
        let r = sync({ [conf]: original }, ["btop"]);
        r = sync(r.files, ["btop"], r.done);           // again: theirs stays the one remembered, not ours
        verify(r.files[conf].indexOf('color_theme = "rutile"') >= 0);
        verify(r.files[conf].indexOf('"Default"') < 0);
        let off = sync(r.files, [], r.done);
        compare(off.files[conf], original, "theirs again, in its place");
        r = sync(off.files, ["btop"], off.done);
        r.files[conf] = r.files[conf].replace('"rutile"', '"nord"');
        off = sync(r.files, [], r.done);
        verify(off.files[conf].indexOf('color_theme = "nord"') >= 0, "changed by the user since: left alone");
    }

    function test_qt_keys_in_their_section() {
        const conf = "/h/.config/qt6ct/qt6ct.conf";
        const original = "[Appearance]\nstyle=Fusion\ncustom_palette=false\n\n[Fonts]\nfixed=x\n";
        let r = sync({ [conf]: original }, ["qt"]);
        const text = r.files[conf];
        verify(text.indexOf("custom_palette=true") >= 0);
        verify(text.indexOf("color_scheme_path=/h/.config/qt6ct/colors/rutile.conf") >= 0);
        verify(text.indexOf("color_scheme_path") < text.indexOf("[Fonts]"), "in [Appearance]");
        verify(r.files["/h/.config/qt5ct/qt5ct.conf"].startsWith("[Appearance]\ncolor_scheme_path="), "made when missing");
        const off = sync(r.files, [], r.done);
        compare(off.files[conf], original);
        verify(off.files["/h/.config/qt5ct/qt5ct.conf"].indexOf("color_scheme_path") < 0, "a key that was not there goes");
    }

    function test_switching_between_apps() {
        let r = sync({}, ["ghostty", "nvim"]);
        compare(r.files["/h/.config/ghostty/config"], "# >>> rutile colors >>>\ntheme = rutile\n# <<< rutile colors <<<\n");
        compare(r.themed.join(), "ghostty,nvim");
        r = sync(r.files, ["nvim"], r.done);
        compare(r.files["/h/.config/ghostty/config"], null, "ghostty off: its block (all of it) goes");
        compare(r.files["/h/.config/ghostty/themes/rutile"], null);
        compare(r.files["/h/.config/nvim/colors/rutile.lua"], rendered["nvim.lua"], "nvim stays");
        compare(Object.keys(r.done).join(), "nvim");
    }

    function test_firefox_keeps_theirs_aside() {
        const hosts = "/h/.mozilla/native-messaging-hosts/";
        const theirs = '{"name": "pywalfox", "path": "/nix/store/x-noctalia/bin/noctalia"}\n';
        let r = sync({ [hosts + "pywalfox.json"]: theirs }, ["firefox"]);
        const manifest = JSON.parse(r.files[hosts + "pywalfox.json"]);
        compare(manifest.allowed_extensions.join(), "pywalfox@frewacom.org");
        compare(manifest.path, "/h/.local/share/rutile/pywalfox-host");
        verify(r.files[manifest.path].indexOf("exec python3 '/r/tools/pywalfox_host.py'") > 0);
        compare(r.ops.filter(o => o.op === "write" && o.path === manifest.path)[0].mode, "755", "the wrapper runs");
        compare(r.files[hosts + "pywalfox.json.rutile-backup"], theirs);
        compare(r.files["/h/.cache/rutile/pywalfox.json"], rendered["pywalfox.json"]);
        r = sync(r.files, ["firefox"], r.done);
        compare(r.files[hosts + "pywalfox.json.rutile-backup"], theirs, "theirs kept once, not ours");
        const off = sync(r.files, [], r.done);
        compare(off.files[hosts + "pywalfox.json"], theirs, "theirs back");
        compare(off.files[manifest.path], null);
        compare(off.files[hosts + "pywalfox.json.rutile-backup"], null);
        // its own manifest, after its records were lost, is never kept aside as if it were someone else's
        const lost = sync(r.files, ["firefox"], {});
        compare(lost.ops.filter(o => o.op === "move").length, 0);
        const alone = sync(sync({}, ["firefox"]).files, [], sync({}, ["firefox"]).done);
        compare(alone.files[hosts + "pywalfox.json"], null, "no other host: nothing left");
    }

    function test_unknown_app() {
        const r = sync({}, ["emacs"]);
        compare(r.unknown.join(), "emacs");
        compare(r.ops.length, 0, "nothing done");
    }

    function test_templates_and_paths() {
        compare(AppTheme.templates(dirs, ["gtk", "kitty"]).map(t => t.name).join(), "gtk.css,kitty.conf", "once each");
        compare(AppTheme.templates(dirs, ["gtk"])[0].input, "/r/theme/apps/gtk.css");
        const p = AppTheme.paths(dirs, ["firefox", "btop"]);
        verify(p.indexOf("/h/.mozilla/native-messaging-hosts/pywalfox.json") >= 0);
        verify(p.indexOf("/h/.config/btop/btop.conf") >= 0);
        compare(new Set(p).size, p.length, "no path twice");
        compare(AppTheme.ORDER.join(), "gtk,qt,kitty,ghostty,btop,nvim,firefox");
    }

    function test_text_edits() {
        const c = ["# ", ""];
        compare(AppTheme.stripBlock("a\n# >>> rutile colors >>>\nx\n# <<< rutile colors <<<\nb\n", c), "a\nb\n");
        compare(AppTheme.addBlock("", c, ["x"], "end"), "# >>> rutile colors >>>\nx\n# <<< rutile colors <<<\n");
        compare(count(AppTheme.addBlock(AppTheme.addBlock("a\n", c, ["x"], "end"), c, ["x"], "end"), ">>> rutile"), 1,
                "never twice");
        compare(AppTheme.getKey("[A]\nk=1\n[B]\nk=2\n", "B", "k"), "2");
        compare(AppTheme.getKey("k = 3\n[A]\nk=1\n", null, "k"), "3", "before any section");
        compare(AppTheme.getKey("[A]\n", "A", "k"), null);
        compare(AppTheme.setKey("[A]\nk=1\n[B]\n", "A", "k", null), "[A]\n[B]\n", "null removes");
        compare(AppTheme.setKey("[B]\nx=1\n", "A", "k", "v"), "[B]\nx=1\n\n[A]\nk=v\n", "a new section at the end");
        compare(AppTheme.setKey("x = 1\n", null, "k", "v"), "k = v\nx = 1\n");
        compare(AppTheme.setKey("[A]\nx=1\n", "A", "k", "v"), "[A]\nx=1\nk=v\n", "into the last section, not a second one");
        compare(AppTheme.setKey("[A]\nk=1\n[B]\nz=0\n", "A", "k", "2"), "[A]\nk=2\n[B]\nz=0\n", "in place");
    }

    // ---- Files.js ----
    function test_read_output() {
        const out = "\n@@rutile-file:1:/a\nline one\nline two\n\n@@rutile-file:0:/b\n\n@@rutile-file:1:/c\n\n@@rutile-file:1:/d\nno newline";
        const f = Files.parseRead(out);
        compare(f["/a"], "line one\nline two\n");
        compare(f["/b"], null, "missing");
        compare(f["/c"], "", "empty");
        compare(f["/d"], "no newline");
        compare(Object.keys(Files.parseRead("")).length, 0);
    }

    function test_commands_keep_data_out_of_the_script() {
        const evil = "$(rm -rf ~)\"'`";
        const a = Files.applyCommand([{ op: "write", path: "/p", text: evil }, { op: "remove", path: "/q" },
                                      { op: "move", from: "/x", to: "/y" }, { op: "signal", sig: "USR1", pattern: "kitty" }]);
        compare(a.slice(0, 2).join(), "sh,-c");
        verify(a[2].indexOf(evil) < 0, "the text is an argument, never the script");
        compare(a.slice(4).join("|"), "write|/p|" + evil + "|644|remove|/q|move|/x|/y|signal|USR1|kitty");
        verify(Files.readCommand(["/a b"]).indexOf("/a b") === 4);
        const m = Files.matugenCommand("matugen", "/run/x", [{ name: "gtk.css", input: "/t/gtk.css" }],
                                       ["color", "hex", "#123456"], "scheme-tonal-spot", "dark", 0);
        verify(m[5].indexOf('output_path = "/run/x/out/gtk.css"') > 0, "outputs in the work folder");
        compare(m.slice(6).join(" "), "matugen -q -c /run/x/matugen.toml color hex #123456 -t scheme-tonal-spot -m dark --contrast 0");
        let threw = false;
        try { Files.applyCommand([{ op: "format" }]); } catch (e) { threw = true; }
        verify(threw, "an unknown op is refused");
    }

    // ---- Palette.js ----
    function test_palette_check() {
        const roles = ["primary", "surface"];
        const good = { format: 1, mode: "dark", source_color: "#134aae",
                       colors: { dark: { primary: "#aabbcc", surface: "#000000" }, light: { primary: "#aabbcc", surface: "#ffffff" } } };
        compare(Palette.validate(good, roles).length, 0);
        const bad = JSON.parse(JSON.stringify(good));
        bad.format = 2;
        bad.mode = "dim";
        bad.colors.dark.primary = "#ABC";
        bad.colors.light.extra = "#000000";
        delete bad.colors.light.surface;
        const errs = Palette.validate(bad, roles).join("; ");
        for (const part of ["format must be 1", "mode must be dark or light", "colors.dark.primary is not #rrggbb",
                            "unexpected role \"extra\"", "colors.light missing roles: surface"])
            verify(errs.indexOf(part) >= 0, part + " in " + errs);
        compare(Palette.validate([], roles)[0], "palette is not an object");
        compare(Palette.validate({ format: 1, mode: "dark", source_color: "#000000", colors: { dark: {} } }, roles).pop(),
                "colors must have exactly the keys dark and light");
        const written = JSON.parse(Palette.finish(good, "scheme-vibrant", 0.5));
        compare(written.scheme, "scheme-vibrant");
        compare(written.contrast, 0.5);
        compare(written.colors.dark.primary, "#aabbcc");
        verify(Palette.finish(good, "s", 0).endsWith("}\n"));
    }
}
