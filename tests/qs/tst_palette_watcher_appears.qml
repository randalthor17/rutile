// A palette written after the shell started (the first `palette.py render`, into a directory that did not exist
// yet) is picked up, and so is a later render, which replaces the file atomically (a new file under the name).
// env RUTILE_PALETTE=@WS@/later/palette.json
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

ShellRoot {
    id: root

    property int stage: 0

    QsTest { id: t }
    PaletteWatcher { id: watcher }

    // as palette.py writes: a temporary file in the directory, renamed over the target
    Process {
        id: writer
        function write(color) {
            command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && sed "s/#134aae/$2/" "$0" > "$1.tmp" && mv "$1.tmp" "$1"',
                       Quickshell.env("RUTILE_PALETTE").replace("/later/palette.json", "/palette.json"),
                       watcher.path, color];
            running = true;
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            if (root.stage === 0) {
                t.verify(!Colors.loaded, "nothing at first");
                writer.write("#00aa00");
                root.stage = 1;
            } else if (root.stage === 1 && Colors.sourceColor === "#00aa00") {
                writer.write("#aa0000");
                root.stage = 2;
            } else if (root.stage === 2 && Colors.sourceColor === "#aa0000") {
                t.verify(true, "both renders picked up");
                t.done();
                root.stage = 3;
            }
        }
    }

    Timer {
        interval: 15000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage + " (source " + Colors.sourceColor + ")");
            t.done();
        }
    }
}
