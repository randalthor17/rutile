// AppColorsService (D52, D53) end to end in a sandbox HOME (qtws gives every Quickshell test its own): everything
// off by default, and then nothing is written; an app's switch does nothing until the main switch is on; then the
// real matugen renders the apps' templates from the palette and the files appear, with the palette's colors; a
// new palette themes them again; the main switch off takes everything back out. pkill is a stand-in that logs.
// env PATH=@WS@/bin:@PATH@
// env FAKE_PKILL_LOG=@WS@/pkill.log
// env RUTILE_PALETTE=@WS@/palette.json
// env RUTILE_PYWALFOX_HOST=@WS@/bin/fake-pywalfox-host
// Another program's Firefox host (as Noctalia's) is there first: kept aside while ours is in, then put back.
// Ghostty's config is a link, as home-manager makes it: never changed, and the error says what to add. niri gets its
// own rutile-colors.kdl.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property var files: ({})
    readonly property string home: Quickshell.env("HOME")
    readonly property var watched: [home + "/config/kitty/kitty.conf", home + "/config/kitty/rutile-colors.conf",
                                    home + "/config/gtk-4.0/gtk.css", home + "/config/gtk-4.0/rutile.css",
                                    home + "/.mozilla/native-messaging-hosts/pywalfox.json",
                                    home + "/.mozilla/native-messaging-hosts/pywalfox.json.rutile-backup",
                                    home + "/cache/rutile/pywalfox.conf",
                                    home + "/config/niri/rutile-colors.kdl", home + "/config/ghostty/themes/rutile",
                                    home + "/hm-ghostty",
                                    Quickshell.env("FAKE_PKILL_LOG")]
    QsTest { id: t }
    readonly property string theirs: '{"name": "pywalfox", "path": "/nix/store/x-noctalia"}'
    Process {
        id: other
        running: true
        command: ["sh", "-c", 'mkdir -p "$HOME/.mozilla/native-messaging-hosts" "$HOME/config/ghostty" && printf "%s" "$1" > "$HOME/.mozilla/native-messaging-hosts/pywalfox.json" && printf "font-size = 12\\n" > "$HOME/hm-ghostty" && ln -s "$HOME/hm-ghostty" "$HOME/config/ghostty/config"',
                  "sh", root.theirs]
    }
    Process {
        id: reader
        command: ["sh", "-c", 'for f do if [ -f "$f" ]; then printf "\\n@@%s\\n" "$f"; cat "$f"; fi; done', "sh"].concat(root.watched)
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                const parts = text.split(/\n@@([^\n]*)\n/);
                for (let i = 1; i < parts.length; i += 2) out[parts[i]] = parts[i + 1];
                root.files = out;
            }
        }
    }
    // a new wallpaper's palette: another source color
    Process {
        id: repaint
        command: ["sh", "-c", 'sed -i "s/\\"source_color\\": \\"#[0-9a-f]*\\"/\\"source_color\\": \\"#9c2b2b\\"/" "$RUTILE_PALETTE"']
    }
    function file(name) { return files[home + name]; }
    Timer {
        interval: 900
        repeat: true
        running: true
        onTriggered: {
            if (reader.running || repaint.running || other.running) return;
            const S = AppColorsService;
            switch (root.stage) {
            case 0:
                t.verify(home.indexOf("rutile-qs-") > 0, "a sandbox HOME, never the user's: " + home);
                t.verify(!S.enabled, "off by default");
                for (const a of S.apps) t.compare(Settings.value("appColors." + a), false, a + " off by default");
                reader.running = true;
                break;
            case 1:
                t.compare(Object.keys(root.files).join(), root.home + "/.mozilla/native-messaging-hosts/pywalfox.json," + root.home + "/hm-ghostty",
                          "all off: nothing written (only the other program's host and the linked config)");
                t.compare(S.runs, 0, "nothing run");
                Settings.set("appColors.kitty", true);
                Settings.set("appColors.gtk", true);
                Settings.set("appColors.firefox", true);
                Settings.set("appColors.niri", true);
                Settings.set("appColors.ghostty", true);
                break;
            case 2:
                t.compare(JSON.stringify(S.wanted), "[]", "apps on, the main switch off: nothing");
                Settings.set("appColors.enabled", true);
                break;
            case 3:
            case 4:
                if (S.runs < 1) return;                   // matugen takes a moment
                reader.running = true;
                root.stage = 4;
                break;
            case 5: {
                t.verify(S.lastError.indexOf("Ghostty: " + root.home + "/config/ghostty/config is a link (home-manager?), not changed; add theme = rutile") === 0,
                         "only the linked config's warning: " + S.lastError);
                t.compare(root.file("/hm-ghostty"), "font-size = 12\n", "the linked config is not changed");
                t.verify((root.file("/config/ghostty/themes/rutile") ?? "").indexOf("cursor-color = #b2c5ff") >= 0, "Ghostty's theme still comes");
                t.verify((root.file("/config/niri/rutile-colors.kdl") ?? "").indexOf('active-color "#b2c5ff"') > 0, "niri's colors");
                const colors = root.file("/config/kitty/rutile-colors.conf") ?? "";
                t.verify(colors.indexOf("cursor #b2c5ff") >= 0, "kitty wears the palette's primary: " + colors.slice(0, 200));
                t.verify((root.file("/config/kitty/kitty.conf") ?? "").indexOf("include rutile-colors.conf") > 0, "kitty includes it");
                t.verify((root.file("/config/gtk-4.0/gtk.css") ?? "").indexOf("@import 'rutile.css';") > 0, "gtk imports it");
                t.verify((root.file("/config/gtk-4.0/rutile.css") ?? "").indexOf("accent_bg_color #b2c5ff") > 0, "gtk's colors");
                const manifest = JSON.parse(root.file("/.mozilla/native-messaging-hosts/pywalfox.json") ?? "{}");
                t.compare(manifest.path, Quickshell.env("RUTILE_PYWALFOX_HOST"), "Firefox's host manifest: the host itself");
                t.compare(root.file("/.mozilla/native-messaging-hosts/pywalfox.json.rutile-backup"), root.theirs, "theirs kept aside");
                t.verify((root.file("/cache/rutile/pywalfox.conf") ?? "").indexOf("\ncolor1 #b2c5ff\n") > 0, "Firefox's colors");
                t.verify((root.files[Quickshell.env("FAKE_PKILL_LOG")] ?? "").indexOf("-USR1 -f") === 0, "kitty told to reload");
                t.compare(S.synced.join(), "niri,gtk,kitty,ghostty,firefox", "remembered");
                repaint.running = true;
                break;
            }
            case 6:
            case 7:
                if (S.runs < 2) return;
                reader.running = true;
                root.stage = 7;
                break;
            case 8: {
                const colors = root.file("/config/kitty/rutile-colors.conf") ?? "";
                t.verify(colors.indexOf("cursor #b2c5ff") < 0 && colors.indexOf("cursor #") >= 0,
                         "a new palette: new colors " + colors.slice(0, 200));
                Settings.set("appColors.enabled", false);
                break;
            }
            case 9:
            case 10:
                if (S.runs < 3) return;
                reader.running = true;
                root.stage = 10;
                break;
            case 11: {
                const left = Object.keys(root.files).filter(f => f !== Quickshell.env("FAKE_PKILL_LOG"));
                t.compare(left.join(), root.home + "/.mozilla/native-messaging-hosts/pywalfox.json," + root.home + "/hm-ghostty",
                          "the main switch off: everything taken back out");
                t.compare(root.file("/hm-ghostty"), "font-size = 12\n", "the linked config never changed");
                t.compare(root.file("/.mozilla/native-messaging-hosts/pywalfox.json"), root.theirs, "theirs back");
                t.compare(S.synced.join(), "", "nothing themed");
                t.compare(S.lastError, "", "no error");
                t.done();
                break;
            }
            default:
                return;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 40000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
