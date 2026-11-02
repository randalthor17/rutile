// Settings > Input into niri (D70), end to end in a sandbox XDG_CONFIG_HOME: on writes rutile-input.kdl, which
// `niri validate` accepts included after a config of its own; a change rewrites it; a flag off is left out; off
// removes the file. Without niri on PATH the validation is skipped (logged), the rest still runs.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property string out: ""
    readonly property string file: Quickshell.env("XDG_CONFIG_HOME") + "/niri/rutile-input.kdl"
    QsTest { id: t }
    Process {
        id: look
        // the file, and niri's verdict on a config that includes it after a touchpad section of its own
        command: ["sh", "-c", 'if [ ! -f "$1" ]; then echo "file=none"; exit 0; fi; cat "$1"; ' +
                  'd=$(mktemp -d); printf "input {\\n    touchpad {\\n        tap\\n    }\\n}\\ninclude \\"%s\\"\\n" "$1" > "$d/config.kdl"; ' +
                  'if command -v niri >/dev/null; then niri validate -c "$d/config.kdl" >/dev/null 2>&1 && echo "niri=valid" || echo "niri=invalid"; ' +
                  'else echo "niri=missing"; fi; rm -rf "$d"', "sh", root.file]
        stdout: StdioCollector { onStreamFinished: root.out = text }
    }
    Timer {
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            if (look.running) return;
            switch (root.stage) {
            case 0:
                t.compare(NiriInputService.written, "?", "off at start: a file left from before would be removed");
                look.running = true;
                break;
            case 1:
                t.verify(root.out.indexOf("file=none") >= 0, "off: no file");
                Settings.set("input.enabled", true);
                break;
            case 2:
                look.running = true;
                break;
            case 3:
                t.verify(root.out.indexOf("repeat-delay 600") >= 0 && root.out.indexOf("repeat-rate 25") >= 0, "the defaults: " + root.out);
                t.verify(/touchpad \{\n\s+tap\n\s+natural-scroll\n\s+accel-speed 0\n/.test(root.out), "touchpad");
                t.verify(root.out.indexOf('accel-profile "adaptive"') >= 0);
                if (root.out.indexOf("niri=missing") >= 0) console.log("QSTEST SKIPPED (part): no niri to validate with");
                else t.verify(root.out.indexOf("niri=valid") >= 0, "niri takes it: " + root.out);
                Settings.set("input.repeatDelay", 300);
                Settings.set("input.touchpadTap", false);
                Settings.set("input.mouseSpeed", -0.3);
                Settings.set("input.mouseFlat", true);
                break;
            case 4:
                look.running = true;
                break;
            case 5:
                t.verify(root.out.indexOf("repeat-delay 300") >= 0, "a change rewrites it");
                t.verify(!/^\s+tap$/m.test(root.out), "a flag off is left out");
                t.verify(root.out.indexOf("accel-speed -0.3") >= 0 && root.out.indexOf('accel-profile "flat"') >= 0, root.out);
                if (root.out.indexOf("niri=missing") < 0) t.verify(root.out.indexOf("niri=valid") >= 0, "still valid");
                t.compare(NiriInputService.error, "");
                Settings.set("input.enabled", false);
                break;
            case 6:
                look.running = true;
                break;
            case 7:
                t.verify(root.out.indexOf("file=none") >= 0, "off: removed");
                t.compare(NiriInputService.written, "");
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
