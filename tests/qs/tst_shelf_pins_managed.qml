// Pins set in Nix (managed.json) cannot be changed from the shell: no Pin or Unpin, and togglePin refuses.
// env XDG_DATA_DIRS=@WS@/apps
// env XDG_DATA_HOME=@WS@/no-user-apps
// env XDG_CONFIG_HOME=@WS@/config/layers
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
            t.compare(backend.pinnedIds.join(), "firefox", "the pins from managed.json");
            t.verify(!backend.pinsEditable, "not editable");
            t.verify(!backend.togglePin("foot"), "togglePin refuses");
            t.compare(backend.pinnedIds.join(), "firefox", "unchanged");
            t.done();
        }
    }
}
