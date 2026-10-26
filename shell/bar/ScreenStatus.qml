// What the shell shows on one screen's top edge: the status pill (top layer, always visible) and the space it
// reserves, so windows stay below it (niri adds its own gap). The shell makes one per screen.
import QtQuick
import Quickshell
import qs.common

Scope {
    id: root

    required property var screen
    required property var backend
    property bool open: false
    readonly property alias pill: pillWindow
    readonly property real reserved: exclusion.size

    signal clicked()

    StatusWindow {
        id: pillWindow
        screen: root.screen
        backend: root.backend
        open: root.open
        onClicked: root.clicked()
    }

    EdgeExclusion {
        id: exclusion
        screen: root.screen
        edge: "top"
        size: pillWindow.margins.top + pillWindow.implicitHeight
    }
}
