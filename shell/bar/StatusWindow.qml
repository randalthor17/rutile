// The status pill's layer-shell surface at the top right of one screen. Always present, so it is just the pill;
// the shell makes one per screen and opens Quick Settings on the screen whose pill was clicked.
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
    // Above the wallpaper, below windows: part of the desktop, not a bar over apps (maintainer's choice).
    // Not WlrLayer.Background: that is the wallpaper's layer, where stacking between surfaces is not reliable.
    WlrLayershell.layer: WlrLayer.Bottom
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
