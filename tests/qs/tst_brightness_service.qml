// BrightnessService against a fake brightnessctl (tests/qs/bin), which logs every call.
// env PATH=@WS@/bin:@PATH@
// env FAKE_BRIGHTNESS=@WS@/fake-brightness
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root

    QsTest { id: t }

    FileView { id: log; path: Quickshell.env("FAKE_BRIGHTNESS") + ".log"; blockLoading: true }

    property int stage: 0

    Connections {
        target: BrightnessService
        function onAvailableChanged() {
            if (root.stage !== 0 || !BrightnessService.available) return;
            root.stage = 1;
            t.compare(BrightnessService.device, "intel_backlight", "device from brightnessctl -m");
            t.compare(BrightnessService.maximum, 1060, "maximum");
            t.verify(Math.abs(BrightnessService.value - 512 / 1060) < 1e-9, "value " + BrightnessService.value);
            // three quick changes: the first is written, the middle one is dropped, the last follows
            BrightnessService.set(0.5);
            BrightnessService.set(0.6);
            BrightnessService.set(0.7);
            t.verify(Math.abs(BrightnessService.value - 742 / 1060) < 1e-9, "shows the newest value at once");
            finish.start();
        }
    }

    Timer {
        id: finish
        interval: 1500
        onTriggered: {
            log.reload();
            var calls = log.text().trim().split("\n");
            t.compare(calls[0], "-m -c backlight info", "reads first");
            t.compare(calls.slice(1).join(" | "),
                      "-m -c backlight -d intel_backlight set 530 | -m -c backlight -d intel_backlight set 742",
                      "writes the first and the newest value only");
            t.done();
        }
    }

    Timer {
        interval: 8000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage);
            t.done();
        }
    }
}
