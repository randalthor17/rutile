// The OSD's layer-shell surface: centred at the bottom of the screen, above the shelf (it keeps clear of the
// shelf's exclusive zone), on the overlay layer so it shows over full-screen windows too. No keyboard focus. The
// shell creates it in a LazyLoader on a level change (D31) and drops it once the panel has played its closing
// motion (`finished`). The window is as big as the open panel and never resized; the panel's motion happens inside.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: root

    readonly property alias panel: panel

    signal finished()

    anchors.bottom: true
    margins.bottom: Spacing.lg
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.namespace: "rutile-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitWidth: panel.implicitWidth
    implicitHeight: panel.implicitHeight
    color: "transparent"

    OsdPanel {
        id: panel
        width: root.implicitWidth
        height: root.implicitHeight
        value: kind === "brightness" ? BrightnessService.value : AudioService.volume
        muted: AudioService.muted
        onMoved: (kind, v) => {
            if (kind === "brightness") BrightnessService.set(v);
            else AudioService.setVolume(v);
        }
        onHidden: root.finished()
    }
}
