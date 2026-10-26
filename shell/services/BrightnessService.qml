// The display backlight through brightnessctl (D39), which writes through systemd-logind, so it needs
// no root, udev rule or setuid wrapper. `available` is false without brightnessctl or a backlight
// (most desktops); hide brightness controls then. brightnessctl reports no changes, so call refresh()
// when showing a control. While a write runs, later values wait and only the newest is sent, so a
// dragged slider does not queue a process per frame.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "BrightnessCtl.js" as Ctl

Singleton {
    id: root

    property bool available: false
    property string device: ""
    property int maximum: 0
    property real value: 0          // 0..1

    property int _pending: -1

    function refresh() {
        if (!reader.running) reader.running = true;
    }

    function set(fraction) {
        if (!available) return;
        var raw = Ctl.rawFor(fraction, maximum);
        value = raw / maximum;
        if (writer.running) {
            _pending = raw;
            return;
        }
        writer.command = Ctl.setCommand(device, raw);
        writer.running = true;
    }

    Process {
        id: reader
        command: Ctl.readCommand()
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var info = Ctl.parse(text);
                if (!info) {
                    root.available = false;
                    return;
                }
                // device and maximum first: anything reacting to `available` may call set() at once
                root.device = info.device;
                root.maximum = info.max;
                if (!writer.running && root._pending < 0) root.value = info.current / info.max;
                root.available = true;
            }
        }
    }

    Process {
        id: writer
        onExited: {
            if (root._pending < 0) return;
            command = Ctl.setCommand(root.device, root._pending);
            root._pending = -1;
            running = true;
        }
    }
}
