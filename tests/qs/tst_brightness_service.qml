// BrightnessService against a fake brightnessctl and a fake ddcutil (tests/qs/bin), which log every call:
// a laptop panel and two monitors (DDC/CI buses 8 and 9), and a third display that does not answer.
// env PATH=@WS@/bin:@PATH@
// env FAKE_BRIGHTNESS=@WS@/fake-brightness
// env FAKE_DDC=@WS@/fake-ddc
// env FAKE_DDC_BUSES=8,9
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root

    QsTest { id: t }

    // the fakes' logs, read afresh each time (a FileView read again can give what it read before)
    property string log: ""
    property string ddcLog: ""
    Process {
        id: logs
        command: ["sh", "-c", 'cat "$1.log"; printf "\\036"; cat "$2.log"', "sh",
                  Quickshell.env("FAKE_BRIGHTNESS"), Quickshell.env("FAKE_DDC")]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\x1e");
                root.log = parts[0];
                root.ddcLog = parts[1] ?? "";
                root.logsRead();
            }
        }
    }
    signal logsRead()

    property int stage: 0
    function near(a, b) { return Math.abs(a - b) < 1e-9; }
    function calls(text) {
        return text.trim().split("\n");
    }

    Connections {
        target: BrightnessService
        function onDisplaysChanged() {
            const d = BrightnessService.displays;
            if (root.stage !== 0 || d.length < 3) return;
            root.stage = 1;
            t.compare(d.map(x => x.id).join(), "backlight:intel_backlight,ddc:8,ddc:9", "backlights first, then monitors");
            t.compare(d.map(x => x.output).join(), ",DP-1,HDMI-A-9", "monitors by their connectors");
            t.compare(d.map(x => x.name).join(), "Built-in display,Fake Monitor 8,Fake Monitor 9");
            t.compare(d.map(x => x.max).join(), "1060,100,100");
            t.verify(root.near(d[0].value, 512 / 1060) && root.near(d[1].value, 0.7), "values " + JSON.stringify(d));
            t.verify(BrightnessService.available);
            t.verify(root.near(BrightnessService.value, 512 / 1060), "value: the first display's");
            // three quick changes to all: each display gets the first written and then only the newest
            BrightnessService.set(0.5);
            BrightnessService.set(0.6);
            BrightnessService.set(0.8);
            t.verify(root.near(BrightnessService.value, 848 / 1060), "shows the newest value at once");
            t.verify(root.near(BrightnessService.displays[2].value, 0.8), "on every display");
            written.start();
        }
    }

    Timer {
        id: written
        interval: 2000
        onTriggered: logs.running = true
    }
    Timer {
        id: one
        interval: 800
        onTriggered: logs.running = true
    }
    onLogsRead: {
        if (stage === 1) {
            t.compare(calls(log).join(" | "),
                      "-m -l -c backlight | -m -c backlight -d intel_backlight set 530 | -m -c backlight -d intel_backlight set 848",
                      "the backlight: read, then the first and the newest value only");
            t.compare(calls(ddcLog).join(" | "),
                      "detect --terse | getvcp 10 --brief --bus 8 | getvcp 10 --brief --bus 9 | "
                      + "setvcp 10 80 --bus 8 --noverify | setvcp 10 80 --bus 9 --noverify",
                      "the monitors: found, read, and each written once with the newest value");
            // one display alone (Settings > Display), then read again
            BrightnessService.setDisplay("ddc:9", 0);
            BrightnessService.setDisplay("nothing", 0.3);
            t.verify(near(BrightnessService.displays[1].value, 0.8) && near(BrightnessService.displays[2].value, 0),
                     "only that one");
            // read while that write runs: the monitor still says 80, but the value shown is kept
            BrightnessService.refresh();
            stage = 2;
            one.start();
        } else if (stage === 2) {
            t.compare(calls(ddcLog).slice(5).join(" | "),
                      "setvcp 10 0 --bus 9 --noverify | getvcp 10 --brief --bus 8 | getvcp 10 --brief --bus 9",
                      "a monitor goes down to 0, its dimmest");
            t.verify(near(BrightnessService.displays[2].value, 0), "not the value read during the write");
            BrightnessService.displays = BrightnessService.displays.map(d => Object.assign({}, d, { value: -1 }));
            BrightnessService.refresh();
            stage = 3;
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: root.stage === 3
        onTriggered: {
            const d = BrightnessService.displays;
            if (!root.near(d[2].value, 0) || !root.near(d[0].value, 848 / 1060)) return;
            t.verify(root.near(d[1].value, 0.8), "a refresh reads every display again");
            t.done();
            running = false;
        }
    }

    Timer {
        interval: 12000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage);
            t.done();
        }
    }
}
