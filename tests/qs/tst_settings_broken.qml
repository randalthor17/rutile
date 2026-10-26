// A settings.json or state.json that does not parse at start: the defaults apply, changes are refused, and the
// files are kept as they are for the user to fix.
// env XDG_CONFIG_HOME=@WS@/config/broken
// env XDG_STATE_HOME=@WS@/config/broken-state
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    QsTest { id: t }
    FileView { id: user; path: Settings.configDir + "/settings.json"; blockLoading: true }
    FileView { id: state; path: Settings.stateDir + "/state.json"; blockLoading: true }
    Component.onCompleted: {
        t.compare(Settings.value("motion.speed"), 1, "the default");
        t.verify(!Settings.set("motion.speed", 3), "refused");
        t.compare(Settings.value("motion.speed"), 1, "unchanged");
        t.compare(Settings.stateValue("launcher.view", "grid"), "grid", "the fallback");
        Settings.setState("launcher.view", "list");
        t.compare(Settings.stateValue("launcher.view", "grid"), "grid", "state is not changed either");
        later.start();
    }
    // a write would be asynchronous: look after it would have landed
    Timer {
        id: later
        interval: 500
        onTriggered: {
            user.reload();
            state.reload();
            t.verify(user.text().indexOf("speed\": 2") > 0 && user.text().indexOf("3") < 0, "settings.json is as it was");
            t.compare(state.text().trim(), "{ \"launcher\":", "state.json is as it was");
            t.done();
        }
    }
}
