// The Power page's backend (plan 5.2) against the system's real UPower and power-profiles-daemon, read only (no
// mode is set): it finds the daemon on the system bus when it is there (busctl), names the mode, and reports the
// battery only for a laptop battery. Without the daemon or busctl it says so in the log, and checks the rest.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services      // as the shell has it: Quickshell makes the qs modules something imports

ShellRoot {
    id: root
    property string bus: ""
    QsTest { id: t }
    Loader {
        id: backend
        source: Qt.resolvedUrl("settingsapp/pages/PowerBackend.qml")
    }
    // the same question asked here, to compare
    Process {
        running: true
        command: ["sh", "-c", "busctl --system list --no-legend --no-pager 2>/dev/null | grep -c PowerProfiles || true"]
        stdout: StdioCollector { onStreamFinished: root.bus = text.trim() }
    }
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            const b = backend.item;
            t.verify(b !== null, "it loads: " + backend.status);
            if (!b) { t.done(); return; }
            t.compare(b.profilesAvailable, Number(root.bus) > 0, "the daemon found as busctl sees it (" + root.bus + ")");
            t.verify(["power-saver", "balanced", "performance"].indexOf(b.profile) >= 0, "a mode: " + b.profile);
            if (b.batteryAvailable) {
                t.verify(b.battery >= 0 && b.battery <= 1, "a charge: " + b.battery);
                t.verify(["charging", "pending", "full", "empty", "discharging"].indexOf(b.state) >= 0, b.state);
            } else {
                t.compare(b.state, "", "no battery: no state");
            }
            console.log("QSTEST note: daemon " + b.profilesAvailable + ", mode " + b.profile + ", battery " + b.batteryAvailable);
            t.done();
        }
    }
}
