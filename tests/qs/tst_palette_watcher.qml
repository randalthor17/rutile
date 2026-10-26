// PaletteWatcher loads palette.json into Colors and reloads it when the file changes.
// env RUTILE_PALETTE=@WS@/palette.json
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

ShellRoot {
    id: root

    property var original: null
    property int stage: 0

    QsTest { id: t }
    PaletteWatcher { id: watcher }

    // Writes the changed palette; the watcher must pick it up on its own.
    FileView { id: writer; path: watcher.path; blockLoading: true }

    Connections {
        target: Colors
        function onLoadedChanged() { root.check() }
        function onSourceColorChanged() { root.check() }
    }

    function check() {
        if (stage === 0 && Colors.loaded) {
            stage = 1;
            t.compare(watcher.path, Quickshell.env("RUTILE_PALETTE"), "RUTILE_PALETTE sets the path");
            t.compare(Colors.sourceColor, "#134aae", "loaded the palette file");
            original = JSON.parse(writer.text());
            var changed = JSON.parse(writer.text());
            changed.source_color = "#ff0000";
            changed.colors.dark.primary = "#123456";
            writer.setText(JSON.stringify(changed));
        } else if (stage === 1 && Colors.sourceColor === "#ff0000") {
            stage = 2;
            t.compare(String(Colors.primary), "#123456", "reloaded after the file changed");
            t.done();
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage + " (loaded " + Colors.loaded + ")");
            t.done();
        }
    }
}
