// A toast (plan 2.8): a short message from the shell, as an M3 snackbar on an inverse surface: an optional icon,
// one line of text and an optional action, a text button in the inverse primary color. show() opens it, or keeps
// it open with the hold started again; it goes after `holdTime`, not while the pointer is on it, and grows and
// fades with the shared popup motion from its bottom left corner (D43). `hidden` fires once it has closed, so its
// owner (ToastWindow) can show the next one or unload.
import QtQuick
import qs.common
import qs.components

Surface {
    id: root

    property string text: ""
    property string iconName: ""
    property string actionText: ""
    property int holdTime: 4000          // ms on screen after it shows
    property real maxWidth: 480
    property bool open: false

    readonly property bool held: hover.hovered
    readonly property alias actionButton: actionControl

    signal actionClicked()
    signal hidden()

    function show() {
        open = true;
        hold.restart();
    }
    function dismiss() {
        open = false;
    }

    // from what the parts would like, not from the row, whose text is narrowed to fit the toast
    readonly property real iconRoom: iconName !== "" ? 20 + Spacing.md : 0
    readonly property real actionRoom: actionText !== "" ? actionControl.implicitWidth + Spacing.md : 0
    implicitWidth: Math.min(maxWidth, iconRoom + label.implicitWidth + actionRoom + 2 * Spacing.lg)
    implicitHeight: Math.max(48, row.implicitHeight + 2 * Spacing.sm)
    radius: Shapes.full
    tone: Colors.inverseSurface

    PopupMotion {
        target: root
        shown: root.open
        origin: Item.BottomLeft
        onHidden: root.hidden()
    }

    Timer {
        id: hold
        interval: root.holdTime
        onTriggered: if (!root.held) root.open = false
    }
    onHeldChanged: if (!held && open) hold.restart()

    HoverHandler { id: hover }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: Spacing.lg
        width: root.width - 2 * Spacing.lg
        spacing: Spacing.md

        Icon {
            visible: root.iconName !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: 20
            color: Colors.inverseOnSurface
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            // the room the icon and the action leave, or its own width when that is less
            width: Math.max(0, Math.min(implicitWidth, row.width - root.iconRoom - root.actionRoom))
            text: root.text
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Colors.inverseOnSurface
            font: Type.font(Type.bodyMedium)
        }
        Button {
            id: actionControl
            visible: root.actionText !== ""
            anchors.verticalCenter: parent.verticalCenter
            type: "text"
            colors: Object.assign({}, ControlSpec.buttonTypes.text,
                                  { content: "inversePrimary", unselectedContent: "inversePrimary" })
            text: root.actionText
            onClicked: {
                root.actionClicked();
                root.dismiss();
            }
        }
    }
}
