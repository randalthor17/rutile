// The wallpaper's layer-shell surface on one screen (plan 2.9): the whole screen, on the background layer, under
// every window and the shelf, taking no keyboard and no space from windows.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

PanelWindow {
    id: root

    readonly property alias view: view

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rutile-wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    WallpaperView {
        id: view
        anchors.fill: parent
        path: WallpaperService.path
    }
}
