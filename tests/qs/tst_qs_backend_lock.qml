// Quick Settings' power menu: Lock asks the shell to lock (its own lock screen, plan 2.8) and runs no command.
// env PATH=@WS@/bin:@PATH@
import QtQuick
import Quickshell
import qs.quicksettings

ShellRoot {
    id: root
    property int requests: 0
    QsTest { id: t }
    QuickSettingsBackend {
        id: backend
        onLockRequested: root.requests++
    }
    Component.onCompleted: {
        backend.powerAction("lock");
        t.compare(root.requests, 1, "Lock asks the shell to lock");
        backend.powerAction("nope");
        t.compare(root.requests, 1, "an unknown action does nothing");
        t.done();
    }
}
