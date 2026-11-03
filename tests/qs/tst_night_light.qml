// Night light (D91) with a stand-in wlsunset (tests/qs/bin/wlsunset; never the real one): off at first, nothing
// runs; on, wlsunset runs warm all day (its night temperature, one kelvin more for the day); a new warmth restarts
// it; off stops it; and a wlsunset that fails (another program holds the gamma) turns the switch off with a reason.
// env PATH=@WS@/bin:@PATH@
// env FAKE_WLSUNSET_LOG=@WS@/wlsunset.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    readonly property string log: Quickshell.env("FAKE_WLSUNSET_LOG")
    QsTest { id: t }
    FileView {
        id: logFile
        path: root.log
        blockLoading: true
        printErrors: false
    }
    function lines() {
        logFile.reload();
        return logFile.text().split("\n").filter(l => l);
    }
    Process { id: sh }
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            const n = NightLightService;
            switch (root.stage) {
            case 0:
                if (!n.available) return;
                t.verify(!n.on, "off at first");
                t.verify(!n.running, "nothing runs");
                n.setOn(true);
                break;
            case 1:
                if (!n.running || root.lines().length < 1) return;
                t.compare(root.lines()[0], "-t 4000 -T 4001", "warm all day, at the default warmth");
                t.compare(Settings.stateValue("nightLight.on", false), true, "kept in state.json");
                Settings.set("nightLight.temperature", 3000);
                break;
            case 2:
                if (root.lines().length < 2 || !n.running) return;
                t.compare(root.lines()[1], "-t 3000 -T 3001", "a new warmth restarts it");
                t.compare(root.lines().length, 2, "once");
                Settings.set("notifications.sound", false);           // another setting: no restart
                Settings.set("nightLight.schedule", true);
                // the next change comes while the first restart is still stopping wlsunset
                Qt.callLater(() => Settings.set("nightLight.sunset", "20:30"));
                break;
            case 3:
                if (root.lines().length < 3 || !n.running) return;
                t.compare(root.lines()[2], "-t 3000 -T 6500 -S 07:00 -s 20:30", "sunset to sunrise, at the times set");
                t.compare(n.error, "", "a restart is no failure");
                n.setOn(false);
                break;
            case 4:
                if (n.running) return;
                t.compare(n.error, "", "stopped on purpose: no error");
                sh.command = ["touch", root.log + ".fail"];
                sh.running = true;
                break;
            case 5:
                if (sh.running) return;
                n.setOn(true);
                break;
            case 6:
                if (n.on) return;
                t.verify(n.error.indexOf("in use by another client") >= 0, "the reason: " + n.error);
                t.verify(!n.running);
                t.verify((ToastService.current?.text ?? "").indexOf("in use by another client") >= 0, "and a toast says so");
                n.setOn(true);
                break;
            case 7:
                if (n.on || root.lines().length < 5) return;      // tried again when asked
                t.compare(root.lines().length, 5, "once each time");
                t.done();
                break;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
