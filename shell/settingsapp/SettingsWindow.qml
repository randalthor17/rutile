// The settings app's window (plan 5.1): an ordinary app window (xdg toplevel) that the compositor places and
// decorates like any other, in the shell's process so it shares the Settings service, the palette and the fonts.
// The shell creates it only while it is open (D31): closing it (its close button, or niri's close-window)
// unloads it.
import QtQuick
import Quickshell
import qs.common
import qs.services

FloatingWindow {
    id: root

    readonly property alias app: app

    signal finished()

    title: "Settings"
    implicitWidth: 1100
    implicitHeight: 760
    minimumSize: Qt.size(400, 480)
    color: Colors.surfaceContainerLow
    onClosed: root.finished()

    SettingsApp {
        id: app
        anchors.fill: parent
        store: Settings
        focus: true
    }
}
