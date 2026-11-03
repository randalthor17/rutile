// The title bar our own app windows draw (plan 3.1, D88), as Googlebook's: the app's icon and name on the left,
// the caption buttons on the right, on the window's own color. niri draws no title bars, and Qt's are turned off
// (shell.qml), so this is the only one. Plain QtQuick: it asks, and the window (AppFrame) does. Pressing on the
// bar starts a move; a double click and the middle button toggle maximized. No minimize button: niri has no
// minimized state.
import QtQuick
import qs.common

Item {
    id: root

    property string title: ""
    property string iconName: ""
    property bool maximized: false
    property color color: "transparent"

    signal moveRequested()
    signal maximizeRequested()
    signal closeRequested()

    implicitHeight: ControlSpec.iconButtonSizes.s.height + 2 * Spacing.xs
    implicitWidth: titleRow.implicitWidth + buttons.implicitWidth + 3 * Spacing.md

    Rectangle {
        anchors.fill: parent
        color: root.color
    }

    MouseArea {
        id: drag
        objectName: "titleBarDrag"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onPressed: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.moveRequested();
        }
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                root.maximizeRequested();
        }
        onDoubleClicked: root.maximizeRequested()
    }

    Row {
        id: titleRow
        anchors.left: parent.left
        anchors.leftMargin: Spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Spacing.sm

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconName !== ""
            name: root.iconName
            size: ControlSpec.iconButtonSizes.xs.icon
            color: Colors.primary
            fill: 1
        }
        Text {
            objectName: "titleBarTitle"
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width - buttons.width - 4 * Spacing.md)
            elide: Text.ElideRight
            text: root.title
            color: Colors.surfaceOn
            font: Type.font(Type.titleSmall)
        }
    }

    Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: Spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        spacing: Spacing.xs

        IconButton {
            objectName: "titleBarMaximize"
            size: "s"
            iconName: root.maximized ? "filter_none" : "crop_square"
            Accessible.name: root.maximized ? "Restore" : "Maximize"
            onClicked: root.maximizeRequested()
        }
        IconButton {
            objectName: "titleBarClose"
            size: "s"
            iconName: "close"
            Accessible.name: "Close"
            onClicked: root.closeRequested()
        }
    }
}
