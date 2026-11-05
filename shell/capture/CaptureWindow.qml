// The capture bar's layer-shell surface (D120): centered above the shelf, with the keyboard while open. The shell
// creates it in a LazyLoader only while open (D31); close() plays the closing motion, then closeRequested asks the
// shell to unload it (and take what was chosen, once the bar is off the screen).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

PanelWindow {
    id: root

    readonly property bool closing: !bar.shown
    readonly property alias bar: bar
    property var chosen: null               // {mode, target, audio}, taken after the bar is gone

    signal closeRequested()

    function close() { bar.shown = false; }

    anchors.bottom: true
    margins.bottom: Spacing.sm
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    focusable: true
    WlrLayershell.namespace: "rutile-capture"
    implicitWidth: bar.width
    implicitHeight: bar.height
    color: "transparent"

    CaptureBar {
        id: bar
        objectName: "captureBar"
        onCaptureRequested: (mode, target, audio) => {
            root.chosen = { mode: mode, target: target, audio: audio };
            root.close();
        }
        onCloseRequested: root.close()
        onHidden: root.closeRequested()
    }
}
