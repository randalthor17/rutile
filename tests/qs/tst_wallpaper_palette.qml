// WallpaperService (plan 2.9): the palette follows the wallpaper only with wallpaper.palette on; a path already
// rendered (remembered in state.json) is not rendered again. The palette tool is a stand-in that logs.
// env XDG_CONFIG_HOME=@WS@/config/wallpaper-nopalette
// env XDG_STATE_HOME=@WS@/state
// env RUTILE_PALETTE_TOOL=@WS@/bin/fake-palette-tool
// env FAKE_PALETTE_LOG=@WS@/palette.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property string log: ""
    QsTest { id: t }
    // a singleton is created when first used: use it now, so its start-up render (if any) happens before the reads
    Component.onCompleted: console.log("wallpaper " + WallpaperService.path)
    Process {
        id: reader
        command: ["sh", "-c", 'cat "$FAKE_PALETTE_LOG" 2>/dev/null']
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
                t.verify(root.log.indexOf("render --image /tmp/rutile-test-wall.png --out ") === 0, root.log);
                t.compare(Settings.stateValue("wallpaper.paletteFrom", ""), "/tmp/rutile-test-wall.png", "remembered");
                S.renderPalette();                      // as at the next start
                break;
            case 4:
                reader.running = true;
                break;
            case 5:
                t.compare(root.log.split("\n").filter(l => l).length, 1, "the same path is not rendered again");
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
