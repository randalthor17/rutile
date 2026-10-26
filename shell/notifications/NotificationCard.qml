pragma ComponentBehavior: Bound
// One notification (plan 2.8): the app's icon and name and when it came, a close button, the summary and body
// (plain text, NotificationModel.plain), the sender's image at the left when it sent one, and its actions as
// text buttons. A click on the card is the "default" action when there is one. As a popup (`timeout` > 0) it
// asks to go after that many ms, paused while the pointer is over it. Plain QtQuick on
// `notification` (, NotificationModel's shape), so it tests offscreen.
import QtQuick
import qs.common
import qs.components
import "NotificationModel.js" as NotificationModel

Rectangle {
    id: root

    property var notification: ({})
    property int timeout: 0                 // ms; 0: stays
    property real now: Date.now()           // for "5 min"; the owner ticks it
    readonly property var buttons: (notification.actions || []).filter(a => a.id !== "default" && a.text !== "")
    readonly property bool hasDefault: (notification.actions || []).some(a => a.id === "default")
    readonly property bool hovered: stateLayer.hovered || close.hovered

    signal activated()                      // the card was clicked
    signal actionInvoked(string id)
    signal dismissed()                      // the close button
    signal timedOut()

    implicitWidth: 360
    implicitHeight: content.height + 2 * Spacing.lg
    radius: Shapes.extraLarge
    color: Colors.surfaceContainerHigh
    border.width: notification.critical ? 1 : 0
    border.color: Colors.error

    Timer {
        objectName: "notificationTimer"
        interval: root.timeout
        running: root.timeout > 0 && !root.hovered
        onTriggered: root.timedOut()
    }

    StateLayer {
        id: stateLayer
        anchors.fill: parent
        radius: root.radius
        stateColor: Colors.surfaceOn
        onClicked: {
            if (root.hasDefault) root.actionInvoked("default");
            root.activated();
        }
    }

    Column {
        id: content
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - 2 * Spacing.lg
        spacing: Spacing.sm

        // header: icon, app · time, and room for the close button
        Item {
            width: parent.width
            height: Spacing.xl
            Item {
                id: appIcon
                width: Spacing.lg + Spacing.xs
                height: width
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: root.notification.appIcon || ""
                    sourceSize.width: width
                    sourceSize.height: height
                    asynchronous: true
                }
                Loader {
                    anchors.centerIn: parent
                    active: !root.notification.appIcon
                    sourceComponent: Icon { name: "notifications"; size: Spacing.lg + Spacing.xs; color: Colors.surfaceVariantOn }
                }
            }
            Text {
                objectName: "notificationApp"
                x: appIcon.width + Spacing.sm
                width: parent.width - x - close.width - Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: (root.notification.appName || "Notification") + " · "
                      + NotificationModel.ago(root.notification.time || root.now, root.now,
                                              d => d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat),
                                              d => d.toLocaleDateString(Qt.locale(), Locale.ShortFormat))
                elide: Text.ElideRight
                color: Colors.surfaceVariantOn
                font: Type.font(Type.labelMedium)
            }
            IconButton {
                id: close
                objectName: "notificationClose"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: "xs"
                iconName: "close"
                Accessible.name: "Dismiss"
                onClicked: root.dismissed()
            }
        }

        Row {
            width: parent.width
            spacing: Spacing.md
            Loader {
                id: picture
                active: !!root.notification.image
                visible: active
                sourceComponent: Image {
                    objectName: "notificationImage"
                    width: Spacing.xxl + Spacing.sm
                    height: width
                    source: root.notification.image
                    sourceSize.width: width
                    sourceSize.height: height
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            Column {
                width: parent.width - (picture.active ? picture.width + parent.spacing : 0)
                spacing: Spacing.xs
                Text {
                    objectName: "notificationSummary"
                    width: parent.width
                    visible: text !== ""
                    text: root.notification.summary || ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Colors.surfaceOn
                    font: Type.font(Type.titleSmall)
                }
                Text {
                    objectName: "notificationBody"
                    width: parent.width
                    visible: text !== ""
                    text: root.notification.body || ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.bodyMedium)
                }
            }
        }

        Loader {
            active: root.buttons.length > 0
            visible: active
            width: parent.width
            sourceComponent: Flow {
                spacing: Spacing.sm
                layoutDirection: Qt.RightToLeft
                Repeater {
                    model: root.buttons.slice(0, 3)
                    Button {
                        required property var modelData
                        objectName: "notificationAction_" + modelData.id
                        type: "tonal"
                        size: "xs"
                        text: modelData.text
                        onClicked: root.actionInvoked(modelData.id)
                    }
                }
            }
        }
    }
}
