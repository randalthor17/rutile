// AppColorsService without a palette file (no wallpaper yet; the first one is set after the shell started): the
// apps take the shell's own colors (Colors.sourceColor, #134aae until a palette loads), and follow when the shell's
// colors change. Before, it stopped at "no palette to take colors from" and never ran again until a restart.
// Real matugen, a sandbox HOME (qtws), pkill a stand-in that logs.
// env PATH=@WS@/bin:@PATH@
// env FAKE_PKILL_LOG=@WS@/pkill.log
// env RUTILE_PALETTE=@WS@/no-such/palette.json
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property int runsBefore: 0
    readonly property string home: Quickshell.env("HOME")
    QsTest { id: t }
    property string kittyText: ""
    Process {
        id: kitty
        command: ["cat", root.home + "/config/kitty/rutile-colors.conf"]
        stdout: StdioCollector { onStreamFinished: root.kittyText = text }
    }
    Timer {
        interval: 700
        repeat: true
        running: true
        onTriggered: {
            const S = AppColorsService;
            if (kitty.running) return;
            switch (root.stage) {
            case 0:
                t.verify(home.indexOf("rutile-qs-") > 0, "a sandbox HOME, never the user's: " + home);
                Settings.set("appColors.kitty", true);
                Settings.set("appColors.enabled", true);
                break;
            case 1:
                if (S.runs < 1) return;
                kitty.running = true;
                break;
            case 2:
                t.compare(S.lastError, "", "no error without a palette file");
                t.verify(root.kittyText.indexOf("cursor #b2c5ff") >= 0, "the shell's own colors (#134aae): " + root.kittyText.slice(0, 200));
                root.runsBefore = S.runs;
                Colors.sourceColor = "#9c2b2b";           // a palette loaded (PaletteWatcher sets it)
                break;
            case 3:
                if (S.runs <= root.runsBefore) return;
                kitty.running = true;
                break;
            case 4:
                t.verify(root.kittyText.indexOf("cursor #b2c5ff") < 0 && root.kittyText.indexOf("cursor #") >= 0,
                         "followed the shell's new colors: " + root.kittyText.slice(0, 200));
                t.done();
                break;
            default:
                return;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 30000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
