// Without brightnessctl the service reports no brightness, so the slider is hidden.
// env PATH=@WS@/nothing
import QtQuick
import Quickshell
import qs.services

ShellRoot {
    QsTest { id: t }
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            t.verify(!BrightnessService.available, "unavailable");
            BrightnessService.set(0.5);
            t.compare(BrightnessService.value, 0, "set does nothing");
            t.done();
        }
    }
}
