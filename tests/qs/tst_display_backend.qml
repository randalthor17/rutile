// The Display page's backend and NiriDisplayService (plan 5.2, D69, D74) with a stand-in `niri`
// (tests/qs/bin/niri; never the session's niri): the backend reads the outputs when loaded, runs changes one at
// a time in order, reads the outputs again after each and keeps niri's complaint about a change that failed; the
// service keeps each changed output (state.json and rutile-display.kdl), applies the kept choices again when
// niri's config.kdl changes (so they win over its own output sections), and a reset drops one.
// env PATH=@WS@/bin:@PATH@
// env FAKE_NIRI_OUTPUTS=@WS@/outputs.json
// env FAKE_NIRI_LOG=@WS@/niri.log
// env NIRI_SOCKET=@WS@/no-niri.sock
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    readonly property string ws: Quickshell.env("FAKE_NIRI_OUTPUTS").replace(/\/outputs\.json$/, "")
    readonly property string displayFile: Quickshell.env("XDG_CONFIG_HOME") + "/niri/rutile-display.kdl"
    readonly property string confFile: Quickshell.env("XDG_CONFIG_HOME") + "/niri/config.kdl"
    QsTest { id: t }
    Loader { id: backend }
    FileView {
        id: logFile
        path: root.ws + "/niri.log"
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: kdl
        path: root.displayFile
        blockLoading: true
        printErrors: false
    }
    Process {
        id: sh
        property string script: ""
        command: ["sh", "-c", script, "sh", Quickshell.env("FAKE_NIRI_OUTPUTS"), Quickshell.env("FAKE_NIRI_LOG"), root.confFile,
                  JSON.stringify({
            "DP-1": { name: "DP-1", make: "Microstep", model: "MSI MP243X", current_mode: 0, vrr_supported: true,
                      vrr_enabled: false, modes: [{ width: 1920, height: 1080, refresh_rate: 60000, is_preferred: true }],
                      logical: { x: 0, y: 0, width: 1920, height: 1080, scale: 1.0, transform: "Normal" } },
            "HDMI-A-1": { name: "HDMI-A-1", make: "Dell", model: "U2720Q", current_mode: 0, vrr_supported: false,
                          vrr_enabled: false, modes: [{ width: 3840, height: 2160, refresh_rate: 60000, is_preferred: true }],
                          logical: { x: 1920, y: 0, width: 2560, height: 1440, scale: 1.5, transform: "Normal" } }
        })]
    }
    function run(script) {
        sh.script = script;
        sh.running = true;
    }
    function logLines() {
        logFile.reload();
        return logFile.text().split("\n").filter(l => l);
    }
    Component.onCompleted: run('printf "%s" "$4" > "$1"; : > "$2"; mkdir -p "$(dirname "$3")"; printf "input {}\\n" > "$3"')
    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (sh.running) return;
            const b = backend.item;
            switch (root.stage) {
            case 0:
                backend.source = Qt.resolvedUrl("settingsapp/pages/DisplayBackend.qml");
                break;
            case 1:
                if (!b || !b.available) return;
                t.compare(b.outputs.map(o => o.name).join(), "DP-1,HDMI-A-1", "read when loaded, by name");
                t.compare(b.kept.length, 0, "nothing kept yet");
                b.command("HDMI-A-1", ["scale", "2"]);
                b.command("DP-1", ["vrr", "on"]);
                b.command("HDMI-A-1", ["transform", "90"]);
                break;
            case 2:
                if (root.logLines().length < 3) return;
                t.compare(logFile.text(), "HDMI-A-1 scale 2\nDP-1 vrr on\nHDMI-A-1 transform 90\n", "in order, one at a time");
                break;
            case 3:
                if (b.kept.length < 2) return;
                t.compare(JSON.stringify(NiriDisplayService.kept["HDMI-A-1"]),
                          JSON.stringify({ on: true, mode: "3840x2160@60.000", scale: 2, transform: "90", vrr: false }), "kept as niri has it");
                t.verify(NiriDisplayService.kept["DP-1"].vrr, "the other too");
                break;
            case 4:
                kdl.reload();
                if (kdl.text().indexOf("HDMI-A-1") < 0) return;
                t.verify(kdl.text().indexOf('output "HDMI-A-1" {\n    mode "3840x2160@60.000"\n    scale 2\n    transform "90"\n}') >= 0,
                         "rutile-display.kdl: " + kdl.text());
                t.verify(kdl.text().indexOf("variable-refresh-rate") >= 0);
                // the user's config changes: the kept choices are applied again, over it
                root.run(': > "$2"; printf "input {}\\n// changed\\n" > "$3"');
                break;
            case 5: {
                const lines = root.logLines();
                if (lines.length < 10) return;
                for (const want of ["DP-1 on", "DP-1 vrr on", "HDMI-A-1 scale 2", "HDMI-A-1 transform 90", "HDMI-A-1 mode 3840x2160@60.000"])
                    t.verify(lines.indexOf(want) >= 0, "applied again: " + want + " in " + lines.join(" | "));
                t.verify(NiriDisplayService.applied >= 2, "at start and on the change");
                b.reset("DP-1");
                break;
            }
            case 6:
                kdl.reload();
                if (kdl.text().indexOf("DP-1") >= 0) return;
                t.compare(b.kept.join(), "HDMI-A-1", "reset: DP-1 no longer kept");
                b.command("VGA-9", ["on"]);
                break;
            case 7:
                if (b.error === "") return;
                t.verify(b.error.indexOf("not found") >= 0, "niri's complaint kept: " + b.error);
                t.done();
                break;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
