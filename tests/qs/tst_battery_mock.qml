// The battery through a stand-in UPower (python-dbusmock's template on the test's private bus, plan 2.13 B0):
// PowerService follows the display device as it discharges, is plugged in and charges.
// mock upower
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    QsTest { id: t }

    // the mock's own methods, as busctl calls them on the (private) system bus
    function mock(args) {
        busctl.command = ["busctl", "--system", "call", "org.freedesktop.UPower", "/org/freedesktop/UPower",
                          "org.freedesktop.DBus.Mock"].concat(args);
        busctl.running = true;
    }
    function display(props) {
        // SetDeviceProperties(o, a{sv}): props as busctl's words
        const words = [];
        for (const k in props) words.push(k, props[k][0], String(props[k][1]));
        mock(["SetDeviceProperties", "oa{sv}", "/org/freedesktop/UPower/devices/DisplayDevice",
              String(Object.keys(props).length)].concat(words));
    }
    Process {
        id: busctl
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("QSTEST busctl: " + text) }
    }

    Component.onCompleted: {
        // a laptop battery at half, discharging, 2.5 h left
        display({ Type: ["u", 2], State: ["u", 2], Percentage: ["d", 50], TimeToEmpty: ["x", 9000],
                  IsPresent: ["b", "true"] });
        stage = 1;
    }

    Timer {
        interval: 100
        repeat: true
        running: root.stage > 0
        onTriggered: {
            const P = PowerService;
            if (root.stage === 1 && P.batteryAvailable && Math.abs(P.battery - 0.5) < 1e-9) {
                t.verify(!P.charging, "discharging");
                root.display({ State: ["u", 1], Percentage: ["d", 51] });        // plugged in: charging
                root.stage = 2;
            } else if (root.stage === 2 && P.charging) {
                t.verify(Math.abs(P.battery - 0.51) < 1e-9, "the charge follows");
                root.display({ Type: ["u", 1] });                                 // mains: no laptop battery
                root.stage = 3;
            } else if (root.stage === 3 && !P.batteryAvailable) {
                t.verify(true, "not a battery: none shown");
                t.done();
                root.stage = 4;
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage + ": available " + PowerService.batteryAvailable
                     + ", battery " + PowerService.battery + ", charging " + PowerService.charging);
            t.done();
        }
    }
}
