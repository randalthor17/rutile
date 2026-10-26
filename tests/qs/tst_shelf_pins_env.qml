// RUTILE_SHELF_PINS chooses the pins; an id that is not installed is skipped.
// env XDG_DATA_DIRS=@WS@/apps
// env XDG_DATA_HOME=@WS@/no-user-apps
// env RUTILE_SHELF_PINS=foot,not-installed,firefox
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
            t.compare(backend.pinnedIds.join(), "foot,not-installed,firefox", "pins from the environment");
            t.compare(backend.pinned.map(i => i.id).join(), "foot,firefox", "only installed ones show");
            t.done();
        }
    }
}
