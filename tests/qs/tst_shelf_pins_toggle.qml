// Pin and Unpin save shelf.pins, starting from the pins shown (here the defaults: no settings file).
// env XDG_DATA_DIRS=@WS@/apps
// env XDG_DATA_HOME=@WS@/no-user-apps
import QtQuick
import Quickshell
import qs.shelf

ShellRoot {
    QsTest { id: t }
    ShelfBackend { id: backend }
    Timer {
        interval: 1000
        running: true
        onTriggered: {
            t.compare(backend.pinnedIds.join(), "org.gnome.Nautilus,firefox,foot", "the defaults");
            t.verify(backend.pinsEditable, "editable");
            t.verify(backend.togglePin("firefox"), "unpin");
            t.compare(backend.pinnedIds.join(), "org.gnome.Nautilus,foot", "gone, the rest in order");
            t.verify(backend.togglePin("firefox"), "pin");
            t.compare(backend.pinnedIds.join(), "org.gnome.Nautilus,foot,firefox", "back, at the end");
            t.done();
        }
    }
}
