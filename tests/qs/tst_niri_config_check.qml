// niri's config must include rutile.kdl for the shell's niri files to apply (D72): turning on Settings > Input
// with a config.kdl that does not include it says so in a toast, once; a commented line does not count; the
// config is watched, so adding the include is seen at once. The config is read only.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    readonly property string conf: Quickshell.env("XDG_CONFIG_HOME") + "/niri/config.kdl"
    readonly property string inputError: NiriInputService.error     // created as the shell creates it
    QsTest { id: t }
    Process {
        id: write
        property string body: ""
        command: ["sh", "-c", 'mkdir -p "$(dirname "$1")"; printf "%s" "$2" > "$1"', "sh", root.conf, body]
    }
    function put(text) {
        write.body = text;
        write.running = true;
    }
    Component.onCompleted: put('// include "rutile.kdl"\ninput {}\n')
    Timer {
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            if (write.running) return;
            switch (root.stage) {
            case 0:
                NiriConfigCheck.check("");       // as if read before the file was written
                break;
            case 1:
                if (NiriConfigCheck.included !== false) return;
                Settings.set("input.enabled", true);
                break;
            case 2:
                if (!ToastService.current) {
                    t.verify(false, "a toast says what to add");
                    t.done();
                    return;
                }
                t.verify(ToastService.current.text.indexOf('include optional=true "rutile.kdl"') >= 0, ToastService.current.text);
                t.verify(ToastService.current.text.indexOf(root.conf) >= 0, "and where");
                ToastService.done(ToastService.current.id);
                Settings.set("input.enabled", false);
                Settings.set("input.enabled", true);
                break;
            case 3:
                t.compare(ToastService.current, null, "once per run");
                root.put('input {}\ninclude "rutile.kdl"\n');
                break;
            case 4:
                if (NiriConfigCheck.included !== true) return;
                t.verify(true, "the include is seen when the config changes");
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
