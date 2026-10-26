// What the shell shows on one screen's top edge: the clock at the left, the status pill at the right (top layer,
// always visible) and the space they reserve, so windows stay below it (niri adds its own gap). The shell makes one per screen.
import QtQuick
import Quickshell
import qs.common

Scope {
    id: root

    required property var screen
    required property var backend
    property bool open: false
    property bool notificationsOpen: false
    readonly property alias pill: pillWindow
    readonly property alias clock: clockWindow
    readonly property real reserved: exclusion.size

    signal clicked()
    signal bellClicked()

    StatusWindow {
        id: pillWindow
        screen: root.screen
        backend: root.backend
        open: root.open
        notificationsOpen: root.notificationsOpen
        onClicked: root.clicked()
        onBellClicked: root.bellClicked()
    }

    ClockWindow {
        id: clockWindow
        screen: root.screen
    }

    EdgeExclusion {
        id: exclusion
        screen: root.screen
        edge: "top"
        size: pillWindow.margins.top + pillWindow.implicitHeight
    }
}
