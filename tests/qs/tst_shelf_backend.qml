// ShelfBackend against fixture apps (tests/qs/apps) only: the default pins are the first installed app of each
// group, hidden apps are not offered, and icons resolve through the icon theme or come back empty.
// env XDG_DATA_DIRS=@WS@/apps
// env XDG_DATA_HOME=@WS@/no-user-apps
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
            t.compare(backend.pinnedIds.join(), "org.gnome.Nautilus,firefox,foot", "default pins");
            t.compare(backend.items.map(i => i.id).join(), "org.gnome.Nautilus,firefox,foot", "items");
            t.compare(backend.items[1].name, "Firefox", "name from the entry");
            t.verify(backend.items.every(i => i.pinned && !i.running), "pinned, not running (no compositor)");
            t.verify(backend.items.every(i => typeof i.icon === "string"), "icon URLs");
            t.compare(backend.windows.length, 0, "no windows offscreen");
            t.done();
        }
    }
}
