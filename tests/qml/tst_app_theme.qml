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
                                   theme: "/r/theme/apps", host: "/r/build/rutile-pywalfox-host" })
    readonly property string built: "?/r/build/rutile-pywalfox-host"     // the host's existence check
    readonly property var rendered: ({ "gtk.css": "@define-color accent_bg_color #aabbcc;\n", "kitty.conf": "cursor #aabbcc\n",
                                       "btop.theme": "theme[main_bg]=\"#000000\"\n", "qtct.conf": "[ColorScheme]\n",
                                       "ghostty": "background = #111111\n", "nvim.lua": "-- rutile\n",
                                       "pywalfox.conf": "mode dark\n", "niri.kdl": "layout {}\n",
                                       "kdeglobals.colors": "# scheme\n[Colors:View]\nBackgroundNormal=1,2,3\nForegroundNormal=4,5,6\n" +
                                                            "[Colors:Window]\nBackgroundNormal=7,8,9\n[General]\nColorScheme=Rutile\nName=Rutile\n" })

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
        const withHost = Object.assign({ [built]: "" }, files);
        const p = AppTheme.plan({ dirs: dirs, wanted: wanted, done: done ?? {}, files: withHost, rendered: rendered });
        return { files: run(files, p.ops), done: p.done, ops: p.ops, themed: p.themed, unknown: p.unknown, errors: p.errors };
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

    // home-manager's configs are links into the read-only store: replacing one would break the next switch.
    function test_a_linked_config_is_left_alone() {
        const conf = "/h/.config/kitty/kitty.conf", qt6 = "/h/.config/qt6ct/qt6ct.conf";
        const theirs = "font_size 12\n";
        let r = sync({ [conf]: theirs, ["!" + conf]: "", [qt6]: "[Appearance]\n", ["!" + qt6]: "" }, ["kitty", "qt"]);
        compare(r.files[conf], theirs, "not changed");
        compare(r.ops.filter(o => o.path === conf || o.path === qt6).length, 0, "no op touches a link");
        compare(r.files["/h/.config/kitty/rutile-colors.conf"], rendered["kitty.conf"], "its own file still comes");
        const errors = r.errors.join("; ");
        verify(errors.indexOf("kitty: " + conf + " is a link (home-manager?), not changed; add include rutile-colors.conf") === 0, errors);
        verify(errors.indexOf(qt6 + " is a link (home-manager?), not changed; set [Appearance] color_scheme_path = ") > 0, errors);
        verify(!(qt6 + "|Appearance|color_scheme_path" in r.done.qt.previous), "nothing to put back");
        const off = sync(Object.assign({}, r.files, { ["!" + conf]: "", ["!" + qt6]: "" }), [], r.done);
        compare(off.files[conf], theirs, "turned off: still not touched");
        compare(off.files["/h/.config/kitty/rutile-colors.conf"], null);
        // not a link: changed as before
        verify(sync({ [conf]: theirs, ["!" + conf]: null }, ["kitty"]).files[conf].indexOf("include rutile-colors.conf") > 0);
    }

    // Themed while a plain file, then home-manager took the file over (keeping our lines in it): turning off does not
    // write to the link either.
    function test_a_config_that_became_a_link_is_not_undone() {
        const conf = "/h/.config/kitty/kitty.conf", btop = "/h/.config/btop/btop.conf";
        const r = sync({ [conf]: "font_size 12\n", [btop]: "color_theme = \"Default\"\n" }, ["kitty", "btop"]);
        const linked = Object.assign({}, r.files, { ["!" + conf]: "", ["!" + btop]: "" });
        const off = sync(linked, [], r.done);
        compare(off.files[conf], r.files[conf], "kitty.conf, now a link, untouched");
        compare(off.files[btop], r.files[btop], "btop.conf, now a link, untouched");
        compare(off.ops.filter(o => o.path === conf || o.path === btop).length, 0);
        compare(off.files["/h/.config/btop/themes/rutile.theme"], null, "its own files still go");
    }

    // KDE apps: every key of the scheme into kdeglobals, theirs kept and put back; the rest of the file untouched.
    function test_kde_keys_into_kdeglobals_and_back() {
        const kg = "/h/.config/kdeglobals", scheme = "/h/.local/share/color-schemes/Rutile.colors";
        const theirs = "[General]\nfont=Noto Sans,10\nColorScheme=BreezeDark\n\n[Colors:View]\nBackgroundNormal=20,20,20\nDecorationFocus=1,1,1\n";
        let r = sync({ [kg]: theirs }, ["kde"]);
        compare(r.files[scheme], rendered["kdeglobals.colors"], "the scheme installed for KDE's menus");
        const t = r.files[kg];
        compare(AppTheme.getKey(t, "Colors:View", "BackgroundNormal"), "1,2,3");
        compare(AppTheme.getKey(t, "Colors:View", "DecorationFocus"), "1,1,1", "a key the scheme has not: theirs");
        compare(AppTheme.getKey(t, "Colors:Window", "BackgroundNormal"), "7,8,9", "a group they had not: added");
        compare(AppTheme.getKey(t, "General", "ColorScheme"), "Rutile");
        compare(AppTheme.getKey(t, "General", "font"), "Noto Sans,10", "fonts and the rest stay");
        compare(AppTheme.getKey(t, "General", "Name"), null, "the scheme's own name stays out");
        compare(r.ops.filter(o => o.path === kg).length, 1, "one write for all its keys");
        compare(sync(r.files, ["kde"], r.done).ops.length, 0, "a second sync writes nothing");
        // a KDE app changed one key meanwhile: that one is theirs now
        const changed = Object.assign({}, r.files, { [kg]: AppTheme.setKey(r.files[kg], "Colors:Window", "BackgroundNormal", "50,50,50") });
        const off = sync(changed, [], r.done);
        const back = off.files[kg];
        compare(AppTheme.getKey(back, "Colors:View", "BackgroundNormal"), "20,20,20", "theirs back");
        compare(AppTheme.getKey(back, "General", "ColorScheme"), "BreezeDark");
        compare(AppTheme.getKey(back, "Colors:View", "ForegroundNormal"), null, "a key they had not: gone");
        compare(AppTheme.getKey(back, "Colors:Window", "BackgroundNormal"), "50,50,50", "changed since: kept");
        compare(off.files[scheme], null);
        compare(off.ops.filter(o => o.path === kg).length, 1, "one write back too");
        // a new palette: theirs is still what comes back, not our first colors
        const repaint = Object.assign({}, rendered, { "kdeglobals.colors": rendered["kdeglobals.colors"].replace("1,2,3", "9,9,9") });
        const p2 = AppTheme.plan({ dirs: dirs, wanted: ["kde"], done: r.done, files: r.files, rendered: repaint });
        const files2 = run(r.files, p2.ops);
        compare(AppTheme.getKey(files2[kg], "Colors:View", "BackgroundNormal"), "9,9,9");
        const off2 = sync(files2, [], p2.done);
        compare(AppTheme.getKey(off2.files[kg], "Colors:View", "BackgroundNormal"), "20,20,20", "theirs, after two palettes");
        // made for us alone: gone when off
        const fresh = sync({}, ["kde"]);
        compare(sync(fresh.files, [], fresh.done).files[kg], null, "a kdeglobals we made goes");
        // linked: not changed, and said so
        const linked = sync({ [kg]: theirs, ["!" + kg]: "" }, ["kde"]);
        compare(linked.files[kg], theirs);
        verify(linked.errors.join().indexOf("KDE apps: " + kg + " is a link") === 0, linked.errors.join());
    }

    // home-manager's module writes the line into the linked config itself: then there is nothing to say.
    function test_a_linked_config_that_has_our_line_is_fine() {
        const css = "/h/.config/gtk-4.0/gtk.css", kitty = "/h/.config/kitty/kitty.conf", qt6 = "/h/.config/qt6ct/qt6ct.conf";
        const r = sync({ [css]: '@import url("file:///h/.config/gtk-4.0/rutile.css");\n', ["!" + css]: "",
                         [kitty]: "font_size 12\ninclude rutile-colors.conf\n", ["!" + kitty]: "",
                         [qt6]: "[Appearance]\ncolor_scheme_path=/h/.config/qt6ct/colors/rutile.conf\ncustom_palette=true\n", ["!" + qt6]: "" },
                       ["gtk", "kitty", "qt"]);
        const errors = r.errors.join("; ");
        verify(errors.indexOf(css) < 0 && errors.indexOf(kitty) < 0 && errors.indexOf(qt6) < 0, errors);
        verify(errors.indexOf("/h/.config/gtk-3.0/gtk.css") < 0, "gtk-3.0/gtk.css is no link: edited, no error");
        compare(r.files["/h/.config/gtk-4.0/rutile.css"], rendered["gtk.css"]);
        const without = sync({ [kitty]: "include other.conf\n", ["!" + kitty]: "" }, ["kitty"]);
        verify(without.errors.join().indexOf(kitty + " is a link") > 0, "without our line: said");
    }

    function test_niri_gets_its_own_file_only() {
        const r = sync({ "/h/.config/niri/config.kdl": "layout {}\n" }, ["niri"]);
        compare(r.files["/h/.config/niri/rutile-colors.kdl"], rendered["niri.kdl"]);
        compare(r.ops.map(o => o.op + " " + o.path).join(), "write /h/.config/niri/rutile-colors.kdl", "config.kdl never");
        compare(AppTheme.paths(dirs, ["niri"]).join(), "/h/.config/niri/rutile-colors.kdl", "nothing else read");
        const off = sync(r.files, [], r.done);
        compare(off.files["/h/.config/niri/rutile-colors.kdl"], null, "off: gone, so niri's own colors apply");
        compare(off.files["/h/.config/niri/config.kdl"], "layout {}\n");
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
        compare(manifest.path, "/r/build/rutile-pywalfox-host", "the compiled host itself, no wrapper (D54)");
        compare(manifest.type, "stdio");
        compare(r.files[hosts + "pywalfox.json.rutile-backup"], theirs);
        compare(r.files["/h/.cache/rutile/pywalfox.conf"], rendered["pywalfox.conf"]);
        compare(r.errors.length, 0);
        r = sync(r.files, ["firefox"], r.done);
        compare(r.files[hosts + "pywalfox.json.rutile-backup"], theirs, "theirs kept once, not ours");
        const off = sync(r.files, [], r.done);
        compare(off.files[hosts + "pywalfox.json"], theirs, "theirs back");
        compare(off.files[hosts + "pywalfox.json.rutile-backup"], null);
        compare(off.files["/h/.cache/rutile/pywalfox.conf"], null);
        // its own manifest, after its records were lost, is never kept aside as if it were someone else's
        const lost = sync(r.files, ["firefox"], {});
        compare(lost.ops.filter(o => o.op === "move").length, 0);
        const alone = sync({}, ["firefox"]);
        compare(sync(alone.files, [], alone.done).files[hosts + "pywalfox.json"], null, "no other host: nothing left");
    }

    function test_firefox_without_its_host_built() {
        const hosts = "/h/.mozilla/native-messaging-hosts/";
        const theirs = '{"name": "pywalfox"}\n';
        const p = AppTheme.plan({ dirs: dirs, wanted: ["firefox", "nvim"], done: {}, rendered: rendered,
                                  files: { [built]: null, [hosts + "pywalfox.json"]: theirs } });
        compare(p.errors.join(), "Firefox: its host /r/build/rutile-pywalfox-host is not built (make native)");
        compare(p.themed.join(), "nvim", "the others go ahead");
        verify(!p.ops.some(o => (o.path ?? o.from ?? "").indexOf(".mozilla") >= 0), "no manifest pointing nowhere");
        const r = sync({}, ["firefox"]);                      // themed while it was built...
        const gone = AppTheme.plan({ dirs: dirs, wanted: ["firefox"], done: r.done, rendered: rendered,
                                     files: Object.assign({}, r.files, { [built]: null }) });
        compare(gone.ops.length, 0, "...and then not: what is there stays until it is turned off");
        compare(gone.themed.join(), "firefox");
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
        verify(p.indexOf(built) >= 0, "the host only checked for, never read");
        verify(p.indexOf("/h/.config/btop/btop.conf") >= 0);
        verify(p.indexOf("!/h/.config/btop/btop.conf") >= 0, "a config it edits is checked for being a link");
        verify(AppTheme.paths(dirs, ["kitty"]).indexOf("!/h/.config/kitty/kitty.conf") >= 0, "one it adds a block to too");
        verify(AppTheme.paths(dirs, ["kde"]).indexOf("!/h/.config/kdeglobals") >= 0, "and kdeglobals");
        compare(new Set(p).size, p.length, "no path twice");
        compare(AppTheme.ORDER.join(), "niri,gtk,qt,kde,kitty,ghostty,btop,nvim,firefox");
    }

    function test_text_edits() {
        const c = ["# ", ""];
        compare(AppTheme.stripBlock("a\n# >>> rutile colors >>>\nx\n# <<< rutile colors <<<\nb\n", c), "a\nb\n");
        compare(AppTheme.addBlock("", c, ["x"], "end"), "# >>> rutile colors >>>\nx\n# <<< rutile colors <<<\n");
        compare(count(AppTheme.addBlock(AppTheme.addBlock("a\n", c, ["x"], "end"), c, ["x"], "end"), ">>> rutile"), 1,
                "never twice");
        compare(AppTheme.getKey("[A]\nk=1\n[B]\nk=2\n", "B", "k"), "2");
        compare(JSON.stringify(AppTheme.iniEntries("# c=1\n; d=2\nk0=v\n[A]\n k = v w \n=x\n[B][C]\nz=\n")),
                JSON.stringify([{ section: null, key: "k0", value: "v" }, { section: "A", key: "k", value: "v w" },
                                { section: "B][C", key: "z", value: "" }]), "comments and a nameless key left out");
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
