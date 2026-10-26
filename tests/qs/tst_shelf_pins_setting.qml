// The shelf.pins setting chooses the pins; an id that is not installed is skipped.
// env XDG_DATA_DIRS=@WS@/apps
// env XDG_DATA_HOME=@WS@/no-user-apps
// env XDG_CONFIG_HOME=@WS@/config/pins
import QtQuick
import Quickshell
import qs.shelf

ShellRoot {
    QsTest { id: t }
    ShelfBackend { id: backend }
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            t.compare(backend.pinnedIds.join(), "foot,not-installed,firefox", "pins from settings.json");
            t.compare(backend.pinned.map(i => i.id).join(), "foot,firefox", "only installed ones show");
            t.done();
        }
    }
}
