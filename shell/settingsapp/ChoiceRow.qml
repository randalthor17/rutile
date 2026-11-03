// A row of a page of its own (pages/, D67) with choices, shown like a setting's: the app opens its one choice
// dialog for it (SettingsApp.toggleMenu) and calls `choose(index)`, which says `chosen(index)`. `choices` are the labels;
// `current` is the one shown and checked in the menu. `key` must be unique on the app (it names the open menu).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components

ListItem {
    id: root

    property var app: null
    property string key: ""
    property var choices: []
    property string current: ""

    signal chosen(int index)

    readonly property var row: ({ key: root.key, choices: root.choices, title: root.text, description: root.supportingText })
    readonly property bool menuOpen: app?.menuKey === key

    function choose(index) {
        chosen(index);
    }

    objectName: "choice_" + key
    tone: Colors.surfaceContainer
    onClicked: if (app) app.toggleMenu(root)

    Row {
        spacing: Spacing.xs
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.current
            color: Colors.surfaceVariantOn
            font: Type.font(Type.labelLarge)
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.menuOpen ? "arrow_drop_up" : "arrow_drop_down"
            color: Colors.surfaceVariantOn
        }
    }
}
