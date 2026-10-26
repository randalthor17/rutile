pragma ComponentBehavior: Bound
// The notification list (D47), opened from the bell left of the status pill: a header with Do not disturb, the
// notifications newest first (NotificationCards, created only as they scroll into view), and Clear all. It grows
// in from the top right with the shared popup motion (D43) and closes when another window takes the keyboard,
// like Quick Settings (D41). Plain QtQuick on `notifications` (NotificationModel's data), so it tests offscreen.
import QtQuick
import qs.common
import qs.components

Rectangle {
    id: root

    property var notifications: []
    property bool dnd: false
    property bool shown: true
    property real now: Date.now()
    readonly property real maxListHeight: Spacing.xxxl * 10

    signal dndToggled(bool on)
    signal dismissed(int id)
    signal cleared()
    signal activated(int id)
    signal actionInvoked(int id, string action)
    signal windowFocusLost()
    signal hidden()

    property bool windowActive: Window.active   // not readonly: the offscreen tests cannot move window focus
    property bool hadWindowFocus: false
    onWindowActiveChanged: {
        if (windowActive) hadWindowFocus = true;
        else if (hadWindowFocus) windowFocusLost();
    }

    implicitWidth: 360 + 2 * Spacing.md
    implicitHeight: column.height + 2 * Spacing.md
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.extraLarge
    color: Colors.surfaceContainer

    PopupMotion {
        target: root
        shown: root.shown
        origin: Item.TopRight
        onHidden: root.hidden()
    }

    Column {
        id: column
        x: Spacing.md
        y: Spacing.md
        width: root.width - 2 * Spacing.md
        spacing: Spacing.sm

        Item {
            width: parent.width
            height: Spacing.xxl + Spacing.sm
            Text {
                x: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: Colors.surfaceOn
                font: Type.font(Type.titleMedium)
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                spacing: Spacing.sm
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Do not disturb"
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.labelLarge)
                }
                Switch {
                    objectName: "notificationDnd"
                    anchors.verticalCenter: parent.verticalCenter
                    controlled: true
                    checked: root.dnd
                    onToggled: on => root.dndToggled(on)
                }
            }
        }

        ListView {
            id: list
            objectName: "notificationList"
            width: parent.width
            height: Math.min(contentHeight, root.maxListHeight)
            visible: count > 0
            clip: true
            spacing: Spacing.sm
            boundsBehavior: Flickable.StopAtBounds
            model: root.notifications
            delegate: NotificationCard {
                required property var modelData
                objectName: "notificationItem_" + modelData.id
                width: list.width
                notification: modelData
                now: root.now
                onActivated: root.activated(modelData.id)
                onActionInvoked: action => root.actionInvoked(modelData.id, action)
                onDismissed: root.dismissed(modelData.id)
            }
        }

        Item {
            objectName: "notificationEmpty"
            visible: root.notifications.length === 0
            width: parent.width
            height: Spacing.xxxl * 2
            Column {
                anchors.centerIn: parent
                spacing: Spacing.sm
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.dnd ? "notifications_off" : "notifications"
                    size: Spacing.xl
                    color: Colors.surfaceVariantOn
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications"
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.bodyMedium)
                }
            }
        }

        Item {
            visible: root.notifications.length > 0
            width: parent.width
            height: clear.height
            Button {
                id: clear
                objectName: "notificationClearAll"
                anchors.right: parent.right
                type: "tonal"
                size: "s"
                text: "Clear all"
                onClicked: root.cleared()
            }
        }
    }
}
