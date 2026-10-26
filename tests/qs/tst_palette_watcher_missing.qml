// A missing palette file leaves the built-in colors and warns, instead of failing.
// env RUTILE_PALETTE=@WS@/no-such-palette.json
import QtQuick
import Quickshell
import qs.common

ShellRoot {
    QsTest { id: t }
    PaletteWatcher {}

    Timer {
        interval: 1500
        running: true
        onTriggered: {
            t.verify(!Colors.loaded, "nothing loaded");
            t.compare(Colors.sourceColor, "#134aae", "the built-in palette stays");
            t.done();
        }
    }
}
