// Low battery warnings (plan 2.13 B1, D136) end to end: a stand-in UPower (python-dbusmock) discharges, the shell's
// own notification server shows the warnings: 20% once, 10% in its place, 5% critical and naming UPower's action,
// and plugging in closes it. A new discharge warns again.
// mock upower
// env PATH=@WS@/bin:@PATH@
// env FAKE_PW_PLAY=@WS@/played.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    QsTest { id: t }

    function display(props) {
        const words = [];
        for (const k in props) words.push(k, props[k][0], String(props[k][1]));
        busctl.command = ["busctl", "--system", "call", "org.freedesktop.UPower", "/org/freedesktop/UPower",
                          "org.freedesktop.DBus.Mock", "SetDeviceProperties", "oa{sv}",
                          "/org/freedesktop/UPower/devices/DisplayDevice", String(Object.keys(props).length)].concat(words);
        busctl.running = true;
    }
    Process {
        id: busctl
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("QSTEST busctl: " + text) }
    }
    function battery() { return NotificationService.list.filter(n => n.appName === "Battery"); }

    Component.onCompleted: {
        void NotificationService.list;          // the server, on the test's session bus
        display({ Type: ["u", 2], State: ["u", 2], Percentage: ["d", 50], TimeToEmpty: ["x", 5100], IsPresent: ["b", "true"] });
        stage = 1;
    }

    Timer {
        interval: 150
        repeat: true
        running: root.stage > 0 && root.stage < 9
        property int ticks: 0
        onTriggered: {
            ticks++;
            const P = PowerService;
            const b = root.battery();
            switch (root.stage) {
            case 1:
                if (!P.discharging || Math.abs(P.battery - 0.5) > 1e-9) return;
                t.compare(b.length, 0, "no warning at 50%");
                root.display({ Percentage: ["d", 19] });
                root.stage = 2;
                break;
            case 2:
                if (b.length === 0) return;
                t.compare(b.length, 1);
                t.compare(b[0].summary, "Battery low");
                t.compare(b[0].body, "19%, about 1 h 25 min left. Plug in soon, or turn on Power saver.");
                t.verify(!b[0].critical);
                root.display({ Percentage: ["d", 15] });
                ticks = 0;
                root.stage = 3;
                break;
            case 3:
                if (ticks < 6) return;              // time enough for one that should not come
                t.compare(b.length, 1, "15%: no second warning");
                t.compare(b[0].body.slice(0, 3), "19%");
                root.display({ Percentage: ["d", 9] });
                root.stage = 4;
                break;
            case 4:
                if (!b.length || !b[0].body.startsWith("9%")) return;
                t.compare(b.length, 1, "the 10% one in the 20% one's place");
                root.display({ Percentage: ["d", 4], TimeToEmpty: ["x", 300] });
                root.stage = 5;
                break;
            case 5:
                if (!b.length || !b[0].critical) return;
                t.compare(b.length, 1);
                t.compare(b[0].summary, "Battery critically low");
                t.compare(b[0].body, "4%, about 5 min left. Plug in now: the computer will hibernate soon.",
                          "UPower's action named (the mock's HybridSleep)");
                root.display({ State: ["u", 1] });   // plugged in
                root.stage = 6;
                break;
            case 6:
                if (b.length !== 0) return;
                t.verify(true, "plugged in: the critical one closed");
                root.display({ State: ["u", 2], Percentage: ["d", 18] });   // unplugged again, a new discharge
                root.stage = 7;
                break;
            case 7:
                if (b.length === 0) return;
                t.compare(b[0].summary, "Battery low", "a new discharge warns again");
                Settings.set("power.lowBatteryWarnings", false);
                NotificationService.dismissAll();
                root.display({ Percentage: ["d", 3] });
                ticks = 0;
                root.stage = 8;
                break;
            case 8:
                if (ticks < 6) return;
                t.compare(root.battery().length, 0, "switched off: no warnings");
                t.done();
                root.stage = 9;
                break;
            }
        }
    }

    Timer {
        interval: 20000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage + ": " + JSON.stringify(root.battery()));
            t.done();
        }
    }
}
