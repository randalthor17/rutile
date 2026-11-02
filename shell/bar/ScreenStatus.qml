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
    property var trayItems: []
    property string trayMenuId: ""
    readonly property alias pill: pillWindow
    readonly property alias clock: clockWindow
    readonly property real reserved: exclusion.size

    signal clicked()
    signal bellClicked()
    signal trayMenuRequested(var entry, real right)

    StatusWindow {
        id: pillWindow
        screen: root.screen
        backend: root.backend
        open: root.open
        notificationsOpen: root.notificationsOpen
        onClicked: root.clicked()
        onBellClicked: root.bellClicked()
        trayItems: root.trayItems
        trayMenuId: root.trayMenuId
        // from the screen's right edge, for the menu's window
        onTrayMenuRequested: (entry, right) => root.trayMenuRequested(entry, pillWindow.margins.right + right)
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
