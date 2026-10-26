// The status pill's layer-shell surface at the top right of one screen. Always present, so it is just the pill;
// ScreenStatus.qml pairs it with the space it reserves.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

PanelWindow {
    id: root

    required property var backend
    property bool open: false

    signal clicked()

    anchors.top: true
    anchors.right: true
    margins.top: Spacing.sm
    margins.right: Spacing.sm
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rutile-status"
    // Above windows, always visible; the space for it is reserved by an EdgeExclusion (ScreenStatus.qml).
    WlrLayershell.layer: WlrLayer.Top
    implicitWidth: pill.width
    implicitHeight: pill.height
    color: "transparent"

    StatusPill {
        id: pill
        backend: root.backend
        open: root.open
        onClicked: root.clicked()
    }
}
