// The shell's settings into niri (D70, D74), end to end in a sandbox XDG_CONFIG_HOME: Settings > Input on writes
// rutile-settings.kdl, which `niri validate` accepts included after a config of its own; a change rewrites it (a
// keyboard layout, a flag off left out: niri replaces the user's whole touchpad section with it); niri's animations
// follow the shell's speed, turned on over the user's `off` (and none at speed 0); Settings > Windows writes one
// window rule after the user's (D88), its parts following the switches; with every part off the file goes. Without niri on PATH the validation is skipped (logged), the rest still runs.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property string out: ""
    readonly property string file: Quickshell.env("XDG_CONFIG_HOME") + "/niri/rutile-settings.kdl"
    readonly property string serviceError: NiriSettingsService.error     // created as the shell creates it
    QsTest { id: t }
    Process {
        id: look
        // the file, and niri's verdict on a config that includes it after sections of its own
        command: ["sh", "-c", 'if [ ! -f "$1" ]; then echo "file=none"; exit 0; fi; cat "$1"; ' +
                  'd=$(mktemp -d); printf "window-rule {\\n    open-floating false\\n}\\ninput {\\n    touchpad {\\n        tap\\n    }\\n}\\nanimations {\\n    off\\n    slowdown 3\\n}\\ninclude \\"%s\\"\\n" "$1" > "$d/config.kdl"; ' +
                  'if command -v niri >/dev/null; then niri validate -c "$d/config.kdl" >/dev/null 2>&1 && echo "niri=valid" || echo "niri=invalid"; ' +
                  'else echo "niri=missing"; fi; rm -rf "$d"', "sh", root.file]
        stdout: StdioCollector { onStreamFinished: root.out = text }
    }
    function valid() {
        if (root.out.indexOf("niri=missing") >= 0) console.log("QSTEST SKIPPED (part): no niri to validate with");
        else t.verify(root.out.indexOf("niri=valid") >= 0, "niri takes it: " + root.out);
    }
    Timer {
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            if (look.running) return;
            switch (root.stage) {
            case 0:
                look.running = true;
                break;
            case 1:
                t.verify(root.out.indexOf("file=none") >= 0, "nothing on: no file");
                Settings.set("input.enabled", true);
                break;
            case 2:
                look.running = true;
                break;
            case 3:
                t.verify(root.out.indexOf("repeat-delay 600") >= 0 && root.out.indexOf("repeat-rate 25") >= 0, "the defaults: " + root.out);
                t.verify(/touchpad \{\n\s+tap\n\s+dwt\n\s+natural-scroll\n\s+accel-speed 0\n/.test(root.out), "touchpad: " + root.out);
                t.verify(root.out.indexOf("xkb") < 0, "no layout set: niri's own");
                t.verify(root.out.indexOf("animations") < 0, "animations off by default");
                root.valid();
                Settings.set("input.repeatDelay", 300);
                Settings.set("input.touchpadTap", false);
                Settings.set("input.keyboardLayout", "de");
                Settings.set("motion.niri", true);
                Motion.speed = 2;
                break;
            case 4:
                look.running = true;
                break;
            case 5:
                t.verify(root.out.indexOf("repeat-delay 300") >= 0, "a change rewrites it");
                t.verify(!/^\s+tap$/m.test(root.out), "a flag off is left out");
                t.verify(/xkb \{\n\s+layout "de"\n\s+\}/.test(root.out), "the layout: " + root.out);
                t.verify(/animations \{\n\s+on\n\s+slowdown 0\.5\n\}/.test(root.out), "twice as fast: half the slowdown, on over the user's off");
                root.valid();
                Motion.speed = 0;
                Settings.set("input.enabled", false);
                break;
            case 6:
                look.running = true;
                break;
            case 7:
                t.verify(root.out.indexOf("input {") < 0, "input off: gone from the file");
                t.verify(/animations \{\n\s+off\n\}/.test(root.out), "speed 0: no animations");
                t.verify(root.out.indexOf("window-rule") < 0, "windows off by default");
                root.valid();
                Settings.set("motion.niri", false);
                Settings.set("windows.enabled", true);
                break;
            case 8:
                look.running = true;
                break;
            case 9:
                t.verify(/window-rule \{\n\s+open-floating true\n\s+geometry-corner-radius 16\n\s+clip-to-geometry true\n/.test(root.out), "windows: " + root.out);
                t.verify(/shadow \{\n\s+on\n\s+\}/.test(root.out), "a shadow");
                t.verify(/focus-ring \{\n\s+off\n\s+\}\n\s+border \{\n\s+off\n\s+\}/.test(root.out), "no focus ring, no border");
                t.verify(root.out.indexOf("animations") < 0 && root.out.indexOf("input {") < 0, "only the windows part");
                root.valid();
                Settings.set("windows.floating", false);
                Settings.set("windows.cornerRadius", 8);
                Settings.set("windows.shadow", false);
                Settings.set("windows.focusRing", true);
                break;
            case 10:
                look.running = true;
                break;
            case 11:
                t.verify(root.out.indexOf("open-floating") < 0, "not floating: niri's columns");
                t.verify(root.out.indexOf("geometry-corner-radius 8") >= 0, "the radius: " + root.out);
                t.verify(root.out.indexOf("shadow") < 0, "no shadow");
                t.verify(root.out.indexOf("focus-ring") < 0 && root.out.indexOf("border") < 0, "the ring left to niri");
                root.valid();
                Settings.set("windows.enabled", false);
                break;
            case 12:
                look.running = true;
                break;
            case 13:
                t.verify(root.out.indexOf("file=none") >= 0, "every part off: removed");
                t.compare(NiriSettingsService.error, "");
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
