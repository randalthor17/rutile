// The Display page's backend (plan 5.2) with a stand-in `niri` (tests/qs/bin/niri; never the session's niri):
// it reads the outputs when loaded, runs changes one at a time in order and reads the outputs again after each,
// and keeps niri's complaint about a change that failed.
// env PATH=@WS@/bin:@PATH@
// env FAKE_NIRI_OUTPUTS=@WS@/outputs.json
// env FAKE_NIRI_LOG=@WS@/niri.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services      // as the shell has it: Quickshell makes the qs modules something imports

ShellRoot {
    id: root
    property int stage: 0
    readonly property string ws: Quickshell.env("FAKE_NIRI_OUTPUTS").replace(/\/outputs\.json$/, "")
    QsTest { id: t }
    Loader { id: backend }
    FileView {
        id: logFile
        path: root.ws + "/niri.log"
        blockLoading: true
        printErrors: false
    }
    Process {
        id: setup
        running: true
        command: ["sh", "-c", 'printf "%s" "$1" > "$2"; : > "$3"', "sh", JSON.stringify({
            "DP-1": { name: "DP-1", make: "Microstep", model: "MSI MP243X", current_mode: 0, vrr_supported: true,
                      vrr_enabled: false, modes: [{ width: 1920, height: 1080, refresh_rate: 60000, is_preferred: true }],
                      logical: { x: 0, y: 0, width: 1920, height: 1080, scale: 1.0, transform: "Normal" } },
            "HDMI-A-1": { name: "HDMI-A-1", make: "Dell", model: "U2720Q", current_mode: 0, vrr_supported: false,
                          vrr_enabled: false, modes: [{ width: 3840, height: 2160, refresh_rate: 60000, is_preferred: true }],
                          logical: { x: 1920, y: 0, width: 2560, height: 1440, scale: 1.5, transform: "Normal" } }
        }), Quickshell.env("FAKE_NIRI_OUTPUTS"), Quickshell.env("FAKE_NIRI_LOG")]
        onExited: backend.source = Qt.resolvedUrl("settingsapp/pages/DisplayBackend.qml")
    }
    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            const b = backend.item;
            if (!b) return;
            switch (root.stage) {
            case 0:
                if (!b.available) return;
                t.compare(b.outputs.map(o => o.name).join(), "DP-1,HDMI-A-1", "read when loaded, by name");
                t.compare(b.outputs[1].logical.scale, 1.5);
                b.command("HDMI-A-1", ["scale", "2"]);
                b.command("DP-1", ["vrr", "on"]);
                b.command("HDMI-A-1", ["off"]);
                break;
            case 1:
                logFile.reload();
                if (logFile.text().split("\n").filter(l => l).length < 3) return;
                t.compare(logFile.text(), "HDMI-A-1 scale 2\nDP-1 vrr on\nHDMI-A-1 off\n", "in order, one at a time");
                break;
            case 2:
                if (b.outputs[1]?.logical !== null) return;
                t.compare(b.error, "", "no complaint");
                b.command("VGA-9", ["on"]);
                break;
            case 3:
                if (b.error === "") return;
                t.verify(b.error.indexOf("not found") >= 0, "niri's complaint kept: " + b.error);
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
