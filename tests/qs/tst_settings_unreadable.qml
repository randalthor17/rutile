// A settings.json or state.json that exists but cannot be read (here directories) counts as broken: no changes.
// env XDG_CONFIG_HOME=@WS@/config/unreadable
// env XDG_STATE_HOME=@WS@/config/unreadable-state
import QtQuick
import Quickshell
import qs.services

ShellRoot {
    QsTest { id: t }
    Timer {
        interval: 500
        running: true
        onTriggered: {
            t.compare(Settings.value("motion.speed"), 1, "the default");
            t.verify(!Settings.set("motion.speed", 3), "refused");
            t.compare(Settings.value("motion.speed"), 1, "unchanged");
            Settings.setState("launcher.view", "list");
            t.compare(Settings.stateValue("launcher.view", "grid"), "grid", "state is not changed either");
            t.done();
        }
    }
}
