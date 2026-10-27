// The polkit dialog's layer-shell surface (plan 2.8): the whole screen, on the overlay layer, the desktop behind it
// blurred by the compositor (BackgroundEffect), keyboard taken while it shows, like the power menu. The shell loads
// it only while polkit asks (D31) and unloads it once the dialog has played its closing motion (`finished`).
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var flow: null
    readonly property alias dialog: dialog

    signal finished()

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rutile-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    BackgroundEffect.blurRegion: Region { item: root.contentItem }

    PolkitDialog {
        id: dialog
        anchors.fill: parent
        flow: root.flow
        onHidden: root.finished()
    }
}
