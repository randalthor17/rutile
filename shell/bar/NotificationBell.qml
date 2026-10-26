// The bell left of the status pill (D47): it opens the notification list. A bell with a dot while there are
// notifications, a crossed-out bell while Do not disturb is on; tinted while the list is open, like the pill.
// Plain QtQuick, so it tests offscreen.
import QtQuick
import qs.common
import qs.components

Rectangle {
    id: root

    property int count: 0
    property bool dnd: false
    property bool open: false

    signal clicked()

    readonly property string iconName: dnd ? "notifications_off" : count > 0 ? "notifications_unread" : "notifications"
    readonly property color contentColor: open ? Colors.secondaryContainerOn : Colors.surfaceOn

    implicitWidth: Spacing.xl
    implicitHeight: Spacing.xl
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: open ? Colors.secondaryContainer : Colors.surfaceContainer
    Behavior on color { EffectsColor {} }

    Accessible.role: Accessible.Button
    Accessible.name: count > 0 ? count + " notifications" : "Notifications"

    Icon {
        objectName: "bellIcon"
        anchors.centerIn: parent
        name: root.iconName
        size: Spacing.lg
        fill: root.count > 0 && !root.dnd ? 1 : 0
        color: root.contentColor
    }

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        stateColor: root.contentColor
        onClicked: root.clicked()
    }
}
