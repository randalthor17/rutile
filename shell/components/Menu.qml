pragma ComponentBehavior: Bound
// A menu: a segmented list of choices on a raised surface (the power menu, an app's menu in the launcher). It only
// reports the choice. `items` are [{id, text, icon}] (icon: a Material Symbols name, or ""); `currentIndex` marks
// the keyboard's choice. As wide as its widest item, at least `minimumWidth`. Open and close it with a
// PopupLoader (D43). Items are named `<itemPrefix><id>`.
import QtQuick
import qs.common

Rectangle {
    id: root

    property var items: []
    property int currentIndex: -1
    property real minimumWidth: 220
    property string itemPrefix: "menuItem_"

    signal chosen(string id)

    implicitWidth: Math.max(minimumWidth, widest) + 2 * Spacing.sm
    implicitHeight: list.height + 2 * Spacing.sm
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.large
    color: Colors.surfaceContainerHigh

    property real widest: 0
    function measure() {
        let w = 0;
        for (let i = 0; i < repeater.count; i++) w = Math.max(w, repeater.itemAt(i)?.implicitWidth ?? 0);
        widest = w;
    }

    Column {
        id: list
        x: Spacing.sm
        y: Spacing.sm
        width: parent.width - 2 * Spacing.sm
        spacing: ControlSpec.listSpec.segmentedGap
        Repeater {
            id: repeater
            model: root.items
            onItemAdded: root.measure()     // new items replace all of them, so this sees every width
            ListItem {
                required property var modelData
                required property int index
                objectName: root.itemPrefix + modelData.id
                width: list.width
                position: root.items.length === 1 ? "single"
                        : index === 0 ? "first" : index === root.items.length - 1 ? "last" : "middle"
                text: modelData.text
                iconName: modelData.icon || ""
                selected: index === root.currentIndex
                onClicked: root.chosen(modelData.id)
            }
        }
    }
}
