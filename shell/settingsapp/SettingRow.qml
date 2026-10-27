// One setting in the settings app (plan 5.1), as a list item built from its row (Model.sections): a switch for a
// boolean, a slider for a number with limits, a menu of choices, a file for a path (`pickPath`: the app opens the
// file chooser), or the value as text for a list (its editor comes with its page, 5.2). A setting set in Nix shows its value with a lock and takes no
// changes (D45). Changes go through `store.set(key, value)`; a slider saves once it has been still for a moment, so
// a drag does not write the file at every step. A choice asks the app for its menu (`toggleMenu`): the app shows one
// menu above everything, which a row of its own could not be (later sections are drawn over it).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import "Model.js" as Model
import "Pages.js" as Pages

Item {
    id: root

    required property var row
    required property var store
    property bool highlighted: false
    property string position: "single"
    property bool menuOpen: false           // the app's menu is showing this row's choices

    signal toggleMenu()
    signal pickPath()

    readonly property var current: store?.value(row.key)
    readonly property bool managed: store?.isManaged(row.key) ?? false
    readonly property string shownValue: Model.valueText(row.key, current, Pages.hints)
    readonly property alias item: listItem

    objectName: "setting_" + row.key
    implicitWidth: listItem.implicitWidth
    implicitHeight: listItem.implicitHeight

    ListItem {
        id: listItem
        anchors.fill: parent
        position: root.position
        text: root.row.title
        // what it does, or for a path or a list (nothing beside it) the value
        readonly property bool valueBelow: root.row.kind === "path" || root.row.kind === "list"
        supportingText: {
            if (root.managed)
                return "Set in your Nix configuration" + (root.row.kind === "switch" ? "" : ": " + root.shownValue);
            return valueBelow ? root.shownValue : root.row.description;
        }
        tone: Colors.surfaceContainer
        trailingText: !root.managed && root.row.kind === "slider" ? root.shownValue : ""
        selected: root.highlighted
        enabled: !root.managed

        onClicked: {
            if (root.row.kind === "switch") root.store.set(root.row.key, !root.current);
            else if (root.row.kind === "choice") root.toggleMenu();
            else if (root.row.kind === "path") root.pickPath();
        }

        // ---- the control, by kind ----
        Loader {
            active: root.row.kind === "switch"
            visible: active
            sourceComponent: Switch {
                objectName: "settingSwitch_" + root.row.key
                controlled: true
                checked: root.current === true
                enabled: !root.managed
                onToggled: want => root.store.set(root.row.key, want)
            }
        }
        Loader {
            active: root.row.kind === "slider"
            visible: active
            sourceComponent: Slider {
                id: slider
                objectName: "settingSlider_" + root.row.key
                width: 200
                from: root.row.minimum
                to: root.row.maximum
                stepSize: root.row.step
                value: root.current ?? root.row.minimum
                enabled: !root.managed
                onMoved: v => {
                    value = v;
                    save.restart();
                }
                Timer {
                    id: save
                    interval: 300
                    onTriggered: root.store.set(root.row.key, slider.value)
                }
                Connections {
                    target: root
                    // a change from elsewhere (the file, IPC) moves it again
                    function onCurrentChanged() {
                        if (!save.running) slider.value = Qt.binding(() => root.current ?? root.row.minimum);
                    }
                }
            }
        }
        Loader {
            active: root.row.kind === "choice" && !root.managed
            visible: active
            sourceComponent: Row {
                spacing: Spacing.xs
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.shownValue
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
        Loader {
            active: root.row.kind === "path" && !root.managed
            visible: active
            sourceComponent: Button {
                objectName: "settingChoose_" + root.row.key
                type: "tonal"
                size: "xs"
                text: "Choose…"
                onClicked: root.pickPath()
            }
        }
        Loader {
            active: root.managed
            visible: active
            sourceComponent: Icon {
                name: "lock"
                color: Colors.surfaceVariantOn
            }
        }
    }
}
