pragma ComponentBehavior: Bound
// One notification (plan 2.8): the app's icon and name and when it came, a close button, the summary and body
// (plain text, NotificationModel.plain), the sender's image at the left when it sent one, and its actions as
// text buttons. A click on the card is the "default" action when there is one. As a popup (`timeout` > 0) it
// asks to go after that many ms, paused while the pointer is over it. Swiped sideways past a third of its width it
// slides out and asks to be dismissed; short of that it springs back. A sender that offers an inline reply gets a
// Reply button: it opens a field (Enter sends, Escape closes), and `replying` tells the owner it needs the keyboard. Plain QtQuick on
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
    readonly property var buttons: (notification.actions || []).filter(a => a.id !== "default" && a.id !== "inline-reply" && a.text !== "")
    readonly property bool canReply: (notification.reply || "") !== ""
    property bool replying: false
    readonly property bool hasDefault: (notification.actions || []).some(a => a.id === "default")
    readonly property bool hovered: stateLayer.hovered || close.hovered || swipe.active || replying

    signal activated()                      // the card was clicked
    signal actionInvoked(string id)
    signal dismissed()                      // the close button
    signal timedOut()
    signal replied(string text)

    function sendReply(text) {
        if (text.trim() === "") return;
        replying = false;
        replied(text);
    }

    implicitWidth: 360
    implicitHeight: content.height + 2 * Spacing.lg
    radius: Shapes.extraLarge
    color: Colors.surfaceContainerHigh
    border.width: notification.critical ? 1 : 0
    border.color: Colors.error

    // the swipe: the card follows the pointer sideways, then a spring takes it out or back (D43's speed)
    property real swipeX: 0
    property bool swipedAway: false
    transform: Translate { x: root.swipeX }
    function settleSwipe() {
        swipedAway = Math.abs(swipeX) > width / 3;
        swipeSpring.value = swipeX;
        swipeSpring.target = swipedAway ? Math.sign(swipeX) * (width + Spacing.lg) : 0;
        if (swipeSpring.value !== swipeSpring.target) swipeSpring.settled = false;  // the same target as last time
    }
    DragHandler {
        id: swipe
        objectName: "notificationSwipe"
        target: null
        yAxis.enabled: false
        enabled: !root.swipedAway
        // in scene coordinates: the card moves under the pointer, so its own coordinates would feed back
        onCentroidChanged: if (active) root.swipeX = centroid.scenePosition.x - centroid.scenePressPosition.x
        onActiveChanged: if (!active) root.settleSwipe()
    }
    Spring {
        id: swipeSpring
        dampingRatio: 1             // out or back without bouncing
        onValueChanged: if (!swipe.active) root.swipeX = value
        onSettledChanged: if (settled && root.swipedAway) root.dismissed()
    }

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
            active: (root.buttons.length > 0 || root.canReply) && !root.replying
            visible: active
            width: parent.width
            sourceComponent: Flow {
                spacing: Spacing.sm
                layoutDirection: Qt.RightToLeft
                Button {
                    objectName: "notificationReply"
                    visible: root.canReply
                    type: "tonal"
                    size: "xs"
                    iconName: "reply"
                    text: "Reply"
                    onClicked: root.replying = true
                }
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
    
        // the reply field, only while replying
        Loader {
            active: root.replying
            visible: active
            width: parent.width
            sourceComponent: Rectangle {
                height: Spacing.xxl + Spacing.sm
                radius: height / 2
                color: Colors.surfaceContainerHighest
                TextInput {
                    id: replyField
                    objectName: "notificationReplyField"
                    anchors.left: parent.left
                    anchors.leftMargin: Spacing.lg
                    anchors.right: send.left
                    anchors.rightMargin: Spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    color: Colors.surfaceOn
                    selectionColor: Colors.primary
                    selectedTextColor: Colors.primaryOn
                    font: Type.font(Type.bodyMedium)
                    Component.onCompleted: forceActiveFocus()
                    Keys.onReturnPressed: root.sendReply(text)
                    Keys.onEnterPressed: root.sendReply(text)
                    Keys.onEscapePressed: root.replying = false
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: replyField.text === ""
                        text: root.notification.reply || ""
                        color: Colors.surfaceVariantOn
                        font: replyField.font
                    }
                }
                IconButton {
                    id: send
                    objectName: "notificationSend"
                    anchors.right: parent.right
                    anchors.rightMargin: Spacing.xs
                    anchors.verticalCenter: parent.verticalCenter
                    size: "xs"
                    iconName: "send"
                    enabled: replyField.text.trim() !== ""
                    Accessible.name: "Send"
                    onClicked: root.sendReply(replyField.text)
                }
            }
        }
    }
}
