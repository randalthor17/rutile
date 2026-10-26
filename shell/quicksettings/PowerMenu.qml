pragma ComponentBehavior: Bound
// The menu under Quick Settings' power button (Googlebook's power button with a chevron): lock, sign out, restart
// and shut down as a segmented list. It only reports the choice; the panel asks the backend to act. A full-screen
// power menu over a blurred desktop is planned to replace it (plan 2.8).
import QtQuick
import qs.common
import qs.components
import "PowerActions.js" as PowerActions

Rectangle {
    id: root

    signal chosen(string id)

    implicitWidth: 220
    implicitHeight: list.height + 2 * Spacing.sm
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.large
    color: Colors.surfaceContainerHigh

    Column {
        id: list
        x: Spacing.sm
        y: Spacing.sm
        width: parent.width - 2 * Spacing.sm
        spacing: ControlSpec.listSpec.segmentedGap
        Repeater {
            model: PowerActions.actions
            ListItem {
                required property var modelData
                required property int index
                objectName: "qsPower_" + modelData.id
                width: list.width
                position: PowerActions.actions.length === 1 ? "single"
                        : index === 0 ? "first" : index === PowerActions.actions.length - 1 ? "last" : "middle"
                text: modelData.text
                iconName: modelData.icon
                onClicked: root.chosen(modelData.id)
            }
        }
    }
}
