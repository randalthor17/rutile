// Every display's brightness (D113): backlights (laptop panels) through brightnessctl (D39), which
// writes through systemd-logind, so it needs no root, udev rule or setuid wrapper; external monitors
// through ddcutil over DDC/CI, which needs the user in the `i2c` group (NixOS: hardware.i2c.enable).
// `displays` lists them, backlights first; `value` is the first one's and `set()` sets them all (the
// Quick Settings slider, the brightness keys, the OSD); `setDisplay()` sets one (Settings > Display).
// `available` is false without either tool or with nothing that answers; hide brightness controls then.
// Neither tool reports changes, so call refresh() when showing a control; monitors are looked for at
// start and when screens come and go. While a write runs, later values wait and only each display's
// newest is sent, so a dragged slider does not queue a process per frame.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "BrightnessCtl.js" as Ctl

Singleton {
    id: root

    readonly property bool available: displays.length > 0
    property var displays: []       // [{id, kind, device, output, name, max, value}], value 0..1
    readonly property real value: displays.length > 0 ? displays[0].value : 0

    property var _backlights: []
    property var _monitors: []      // from ddcutil detect: [{bus, output, model}]
    property var _vcp: ({})         // bus: {current, max}
    property var _pending: ({})     // id: the raw value to write next
    property string _writing: ""    // the display being written, "" when none (Process.running lags its exit)

    function refresh() {
        if (!reader.running) reader.running = true;
        readMonitors();
    }

    function readMonitors() {
        if (_monitors.length === 0 || vcpReader.running) return;
        vcpReader.command = Ctl.ddcReadCommand(_monitors.map(m => m.bus));
        vcpReader.running = true;
    }

    function set(fraction) {
        displays.forEach(d => setDisplay(d.id, fraction));
    }

    function setDisplay(id, fraction) {
        const d = displays.find(x => x.id === id);
        if (!d) return;
        const raw = Ctl.rawFor(fraction, d.max, d.kind === "ddc" ? 0 : 1);
        displays = displays.map(x => x.id === id ? Object.assign({}, x, { value: raw / x.max }) : x);
        const pending = Object.assign({}, _pending);
        pending[id] = raw;
        _pending = pending;
        writeNext();
    }

    function writeNext() {
        if (_writing !== "") return;
        const id = Object.keys(_pending)[0];
        if (id === undefined) return;
        const d = displays.find(x => x.id === id);
        const pending = Object.assign({}, _pending);
        const raw = pending[id];
        delete pending[id];
        _pending = pending;
        if (!d) {
            writeNext();
            return;
        }
        _writing = id;
        writer.command = Ctl.command(d, raw);
        writer.running = true;
    }

    // What was read, keeping the value shown for a display with a write running or waiting.
    function merge() {
        const read = Ctl.displays(_backlights, _monitors, _vcp);
        displays = read.map(d => {
            const busy = d.id === _writing || _pending[d.id] !== undefined;
            const shown = displays.find(x => x.id === d.id);
            return busy && shown ? Object.assign({}, d, { value: shown.value }) : d;
        });
    }

    Process {
        id: reader
        command: Ctl.readCommand()
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root._backlights = Ctl.parseAll(text);
                root.merge();
            }
        }
    }

    Process {
        id: detector
        command: Ctl.detectCommand()
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root._monitors = Ctl.parseDetect(text);
                if (root._monitors.length === 0) {
                    root._vcp = {};
                    root.merge();
                } else {
                    root.readMonitors();
                }
            }
        }
    }
    // a monitor plugged in or out: look again
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!detector.running) detector.running = true;
        }
    }

    Process {
        id: vcpReader
        stdout: StdioCollector {
            onStreamFinished: {
                root._vcp = Ctl.parseVcp(text);
                root.merge();
            }
        }
    }

    Process {
        id: writer
        onExited: {
            root._writing = "";
            root.writeNext();
        }
    }
}
