// An M3 basic dialog (plan 1.5), from the Compose tokens (ControlSpec.dialogSpec): an optional icon, a headline
// (centered under an icon), supporting text, whatever the caller puts in it (the default slot), and actions at the
// bottom right. The card only: the caller shows it over a scrim in a window of its own, opened with a PopupLoader
// so it gets PopupMotion (D43). `actions` [{id, text, type}] (type a Button type, "text" when missing) left to
// right; choosing one reports `chosen(id)`. Escape reports `chosen(dismissId)`, Enter `chosen(acceptId)`.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common

Rectangle {
    id: root

    property string iconName: ""
    property string headline: ""
    property string supportingText: ""
    property var actions: []
    property string acceptId: ""            // what Enter chooses ("" none)
    property string dismissId: ""           // what Escape chooses ("" none)
    readonly property var spec: ControlSpec.dialogSpec
    default property alias content: slot.data

    signal chosen(string id)

    readonly property real minWidth: 280
    readonly property real maxWidth: 560

    // as wide as its text unwrapped (a wrapped Text reports its wrapped width), the slot and the actions need
    implicitWidth: Math.max(minWidth, Math.min(maxWidth, Math.max(headlineMetrics.advanceWidth, supportingMetrics.advanceWidth,
                                                                  slot.childrenRect.width, actionRow.implicitWidth)
                                                         + 2 * Spacing.xl))
    implicitHeight: column.implicitHeight + 2 * Spacing.xl
    width: implicitWidth
    height: implicitHeight
    radius: spec.containerShape
    color: Colors[spec.containerColor]
    focus: true

    Accessible.role: Accessible.Dialog
    Accessible.name: headline

    Keys.onEscapePressed: event => {
        if (dismissId === "") return;
        chosen(dismissId);
        event.accepted = true;
    }
    function accept(event) {
        if (acceptId === "") return;
        chosen(acceptId);
        event.accepted = true;
    }
    Keys.onReturnPressed: event => accept(event)
    Keys.onEnterPressed: event => accept(event)

    TextMetrics {
        id: headlineMetrics
        text: root.headline
        font: Type.font(Type[root.spec.headlineFont])
    }
    TextMetrics {
        id: supportingMetrics
        text: root.supportingText
        font: Type.font(Type[root.spec.supportingTextFont])
    }

    Column {
        id: column
        x: Spacing.xl
        y: Spacing.xl
        width: root.width - 2 * Spacing.xl
        spacing: Spacing.lg

        Icon {
            objectName: "dialogIcon"
            visible: root.iconName !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.iconName
            size: root.spec.iconSize
            color: Colors[root.spec.iconColor]
        }
        Text {
            objectName: "dialogHeadline"
            visible: root.headline !== ""
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: root.iconName !== "" ? Text.AlignHCenter : Text.AlignLeft
            text: root.headline
            color: Colors[root.spec.headlineColor]
            font: Type.font(Type[root.spec.headlineFont])
        }
        Text {
            objectName: "dialogSupporting"
            visible: root.supportingText !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.supportingText
            color: Colors[root.spec.supportingTextColor]
            font: Type.font(Type[root.spec.supportingTextFont])
        }
        Item {
            id: slot
            visible: children.length > 0
            width: parent.width
            implicitHeight: childrenRect.height
            height: implicitHeight
        }
        Row {
            id: actionRow
            visible: root.actions.length > 0
            anchors.right: parent.right
            spacing: Spacing.sm
            Repeater {
                model: root.actions
                delegate: Button {
                    id: action
                    required property var modelData
                    objectName: "dialogAction_" + action.modelData.id
                    type: action.modelData.type ?? "text"
                    size: "s"
                    text: action.modelData.text
                    onClicked: root.chosen(action.modelData.id)
                }
            }
        }
    }
}
