// The full-screen power menu (plan 2.8, the maintainer's request): lock, sleep, sign out, restart and shut down as
// large round buttons with their names, in the middle of the screen over the desktop, which the window blurs
// (PowerWindow); a veil in the surface color keeps them readable. A click on a button, or Enter on the one chosen
// with the arrow keys (Tab too), reports it (`chosen`); Escape or a click anywhere else reports `dismissed`. Either
// way it closes itself: the shared popup motion (D43) plays back and `hidden` fires at the end.
// Plain QtQuick, so it tests offscreen; the window runs the action.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import "PowerActions.js" as PowerActions

Item {
    id: root

    property bool shown: true
    property int current: 0              // the button the keyboard is on
    property bool keyboardUsed: false    // the ring shows only once the keyboard moved
    readonly property var actions: PowerActions.actions
    readonly property alias content: row

    signal chosen(string id)
    signal dismissed()
    signal hidden()

    focus: true
    Keys.onLeftPressed: move(-1)
    Keys.onRightPressed: move(1)
    Keys.onTabPressed: move(1)
    Keys.onBacktabPressed: move(-1)
    Keys.onReturnPressed: choose(current)
    Keys.onEnterPressed: choose(current)
    Keys.onSpacePressed: choose(current)
    Keys.onEscapePressed: dismiss()

    function move(step) {
        keyboardUsed = true;
        current = (current + step + actions.length) % actions.length;
    }
    function choose(i) {
        if (!shown || i < 0 || i >= actions.length) return;
        chosen(actions[i].id);          // first, so the choice is known before anything can close
        shown = false;
    }
    function dismiss() {
        if (!shown) return;
        dismissed();
        shown = false;
    }

    // The veil fades with the motion; the blur behind it is the compositor's.
    Rectangle {
        anchors.fill: parent
        color: Colors.surface
        opacity: 0.5 * Math.max(0, Math.min(1, motion.progress))
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        onClicked: root.dismiss()
    }

    Row {
        id: row
        objectName: "powerRow"
        anchors.centerIn: parent
        spacing: Spacing.xl

        Repeater {
            model: root.actions
            delegate: Column {
                id: entry
                required property var modelData
                required property int index
                objectName: "power_" + modelData.id
                readonly property bool isCurrent: root.keyboardUsed && root.current === entry.index
                spacing: Spacing.md

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: button.width + 2 * Spacing.xs
                    height: button.height + 2 * Spacing.xs
                    // the keyboard's ring
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: Colors.secondary
                        visible: entry.isCurrent
                    }
                    IconButton {
                        id: button
                        objectName: "powerButton_" + entry.modelData.id
                        anchors.centerIn: parent
                        size: "l"
                        type: entry.modelData.id === "poweroff" ? "filled" : "tonal"
                        iconName: entry.modelData.icon
                        onClicked: root.choose(entry.index)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: entry.modelData.text
                    color: Colors.surfaceOn
                    font: Type.font(Type.titleMedium)
                }
            }
        }
    }

    PopupMotion {
        id: motion
        target: row
        shown: root.shown
        origin: Item.Center
        onHidden: root.hidden()
    }
}
