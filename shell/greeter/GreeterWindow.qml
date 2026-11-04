// The greeter's surface on one screen (plan 6.2, D97): the whole screen, above everything, the keyboard on the one
// `keyboard` names (the first screen). It only shows; greeter.qml decides.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool keyboard: false
    default property alias content: holder.data

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rutile-greeter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: keyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    Item {
        id: holder
        anchors.fill: parent
    }
}
