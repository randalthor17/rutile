// WallpaperService (plan 2.9): the palette follows the wallpaper only with wallpaper.palette on; a path already
// rendered (remembered in state.json) is not rendered again; a render that is not a valid palette leaves the palette
// as it was. matugen is a stand-in that logs and writes a fixture.
// env XDG_CONFIG_HOME=@WS@/config/wallpaper-nopalette
// env XDG_STATE_HOME=@WS@/state
// env RUTILE_MATUGEN=@WS@/bin/fake-matugen
// env FAKE_MATUGEN_LOG=@WS@/palette.log
// env FAKE_MATUGEN_FIXTURE=@WS@/palette.json
// env FAKE_MATUGEN_BROKEN=@WS@/broken
// env RUTILE_PALETTE=@WS@/out/palette.json
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property string log: ""
    QsTest { id: t }
    Process { id: breaker; command: ["sh", "-c", 'touch "$FAKE_MATUGEN_BROKEN"'] }
    FileView { id: written; path: WallpaperService.palettePath; blockLoading: true; printErrors: false }
    // a singleton is created when first used: use it now, so its start-up render (if any) happens before the reads
    Component.onCompleted: console.log("wallpaper " + WallpaperService.path)
    Process {
        id: reader
        command: ["sh", "-c", 'cat "$FAKE_MATUGEN_LOG" 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: root.log = text }
    }
    Timer {
        interval: 700
        repeat: true
        running: true
        onTriggered: {
            if (reader.running) return;
            const S = WallpaperService;
            switch (root.stage) {
            case 0:
                t.compare(S.path, "/tmp/rutile-test-wall.png", "the wallpaper from settings.json");
                t.verify(!S.paletteFollows, "wallpaper.palette off");
                reader.running = true;
                break;
            case 1:
                t.compare(root.log, "", "off: no palette rendered");
                Settings.set("wallpaper.palette", true);
                break;
            case 2:
                reader.running = true;
                break;
            case 3:
                t.compare(root.log.split("\n").filter(l => l).length, 1, "on: rendered once");
                t.verify(root.log.indexOf(" image /tmp/rutile-test-wall.png -t scheme-tonal-spot -m dark --contrast 0 --source-color-index 0") > 0, root.log);
                t.verify(root.log.indexOf("-q -c ") === 0, "matugen with the shell's own config: " + root.log);
                t.compare(Settings.stateValue("wallpaper.paletteFrom", ""), "/tmp/rutile-test-wall.png", "remembered");
                written.reload();
                t.compare(JSON.parse(written.text()).colors.dark.primary, "#b2c5ff", "the palette written");
                t.compare(JSON.parse(written.text()).scheme, "scheme-tonal-spot", "with how it was made (D52)");
                t.compare(S.lastError, "", "no error");
                S.renderPalette();                      // as at the next start
                break;
            case 4:
                reader.running = true;
                break;
            case 5:
                t.compare(root.log.split("\n").filter(l => l).length, 1, "the same path is not rendered again");
                breaker.running = true;                 // the next render is not a valid palette
                break;
            case 6:
                S.set("/tmp/rutile-test-wall-2.png");
                break;
            case 7:
                reader.running = true;
                break;
            case 8:
                t.compare(root.log.split("\n").filter(l => l).length, 2, "the new path rendered");
                t.verify(S.lastError.indexOf("invalid palette: colors must have exactly the keys dark and light") === 0, S.lastError);
                written.reload();
                t.compare(JSON.parse(written.text()).colors.dark.primary, "#b2c5ff", "the palette as it was");
                t.compare(Settings.stateValue("wallpaper.paletteFrom", ""), "/tmp/rutile-test-wall.png", "not remembered as rendered");
                t.done();
                break;
            default:
                return;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
