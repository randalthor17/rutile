pragma ComponentBehavior: Bound
// A menu: a segmented list of choices on a raised surface (the power menu, an app's menu in the launcher, a tray
// app's menu). It only reports the choice. `items` are [{id, text, icon}] (icon: a Material Symbols name, or "");
// optional: `image` (an image source instead of the icon), `enabled` (false greys it out), `check` ("checkbox" or
// "radio", with `checked`), `submenu` (true: an arrow). `{separator: true}` splits the list into segmented
// groups, a gap apart (M3 Expressive). `currentIndex` marks the keyboard's choice. As wide as its widest item, at
// least `minimumWidth`. Open and close it with a PopupLoader (D43). Items are named `<itemPrefix><id>`.
import QtQuick
import qs.common

Rectangle {
    id: root

    property var items: []
    property int currentIndex: -1
    property real minimumWidth: 220
    property string itemPrefix: "menuItem_"

    signal chosen(string id)

    function checkColor(entry) {
        return entry.checked ? Colors.primary : Colors.surfaceVariantOn;
    }

    implicitWidth: Math.max(minimumWidth, widest) + 2 * Spacing.sm
    implicitHeight: list.height + 2 * Spacing.sm
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.large
    color: Colors.surfaceContainerHigh

    property real widest: 0
    // single | first | middle | last within each group between separators
    readonly property var positions: {
        const out = [];
        for (let i = 0; i < items.length; i++) {
            if (items[i].separator) { out.push(""); continue; }
            const before = i > 0 && !items[i - 1].separator;
            const after = i + 1 < items.length && !items[i + 1].separator;
            out.push(before && after ? "middle" : before ? "last" : after ? "first" : "single");
        }
        return out;
    }
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
            delegate: Loader {
                id: entry
                required property var modelData
                required property int index
                width: list.width
                sourceComponent: modelData.separator ? gap : choice
                Component {
                    id: gap
                    Item { implicitHeight: Spacing.xs; implicitWidth: 0 }
                }
                Component {
                    id: choice
                    ListItem {
                        objectName: root.itemPrefix + entry.modelData.id
                        width: list.width
                        position: root.positions[entry.index] || "single"
                        text: entry.modelData.text
                        iconName: entry.modelData.icon || ""
                        iconSource: entry.modelData.image || ""
                        enabled: entry.modelData.enabled !== false
                        selected: entry.index === root.currentIndex
                        onClicked: root.chosen(entry.modelData.id)
                        Icon {
                            readonly property string kind: entry.modelData.check || ""
                            visible: name !== ""
                            name: entry.modelData.submenu ? "chevron_right"
                                : kind === "checkbox" ? (entry.modelData.checked ? "check_box" : "check_box_outline_blank")
                                : kind === "radio" ? (entry.modelData.checked ? "radio_button_checked" : "radio_button_unchecked")
                                : ""
                            fill: entry.modelData.checked ? 1 : 0
                            size: Spacing.lg + Spacing.xs
                            color: entry.modelData.submenu ? Colors.surfaceVariantOn : root.checkColor(entry.modelData)
                        }
                    }
                }
            }
        }
    }
}
