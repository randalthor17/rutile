// One setting in the settings app (plan 5.1), as a list item built from its row (Model.sections): a switch for a
// boolean, a slider for a number with limits, a menu of choices, a file for a path (`pickPath`: the app opens the
// file chooser), swatches for a color (D65), a button for an action (`runAction`, D66), a notice shown while the
// app's `conditions[when]` holds (D74), or a field to type a text, a number or a list in (commas or spaces between
// a list's items; Enter or leaving the field saves it, D79). A setting set in Nix shows its value with a lock and takes no changes (D45). Changes go through `store.set(key, value)`; a slider saves once it has been still for a moment, so
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
    property bool highlighted: false        // opened from a search: the app draws a ring around it
    property string position: "single"
    property bool menuOpen: false           // the app's menu is showing this row's choices
    property var conditions: ({})           // the app's: a notice shows while its `when` is true

    signal toggleMenu()
    signal pickPath()
    signal runAction()

    readonly property var current: store?.value(row.key)
    readonly property bool managed: store?.isManaged(row.key) ?? false
    // greyed out while the setting it depends on is off (an app's colors under the main switch)
    readonly property bool applies: row.requires === "" || store?.value(row.requires) === true
    readonly property string shownValue: Model.valueText(row.key, current, Pages.hints)
    readonly property alias item: listItem

    objectName: "setting_" + row.key
    visible: row.kind !== "notice" || conditions[row.when] === true
    implicitWidth: listItem.implicitWidth
    implicitHeight: listItem.implicitHeight

    ListItem {
        id: listItem
        anchors.fill: parent
        position: root.position
        text: root.row.title
        // what it does, or for a path or a list (nothing beside it) the value
        readonly property bool valueBelow: root.row.kind === "path" || (root.row.kind === "list" && root.managed)
        supportingText: {
            if (root.managed)
                return "Set in your Nix configuration" + (root.row.kind === "switch" ? "" : ": " + root.shownValue);
            return valueBelow ? root.shownValue : root.row.description;
        }
        tone: root.row.kind === "notice" ? Colors.tertiaryContainer : Colors.surfaceContainer
        iconName: root.row.kind === "notice" ? "info" : ""
        trailingText: !root.managed && root.row.kind === "slider" ? root.shownValue : ""
        enabled: !root.managed && root.applies

        onClicked: {
            if (root.row.kind === "switch") root.store.set(root.row.key, !root.current);
            else if (root.row.kind === "choice") root.toggleMenu();
            else if (root.row.kind === "path") root.pickPath();
            else if (root.row.kind === "action") root.runAction();
        }

        // ---- the control, by kind ----
        Loader {
            active: root.row.kind === "switch"
            visible: active
            sourceComponent: Switch {
                objectName: "settingSwitch_" + root.row.key
                controlled: true
                checked: root.current === true
                enabled: !root.managed && root.applies
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
            active: root.row.kind === "color" && !root.managed
            visible: active
            sourceComponent: Row {
                spacing: Spacing.xs
                Repeater {
                    model: root.row.swatches
                    delegate: Item {
                        id: swatch
                        required property string modelData
                        readonly property bool chosen: root.current === modelData
                        objectName: "settingSwatch_" + modelData
                        width: Spacing.xl
                        height: Spacing.xl
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: Colors.primary
                            visible: swatch.chosen
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 2 * Spacing.xs
                            height: width
                            radius: width / 2
                            color: swatch.modelData
                        }
                        StateLayer {
                            anchors.fill: parent
                            radius: width / 2
                            onClicked: root.store.set(root.row.key, swatch.modelData)
                        }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: swatch.modelData
                        Accessible.checked: swatch.chosen
                    }
                }
            }
        }
        Loader {
            active: (root.row.kind === "text" || root.row.kind === "list") && !root.managed
            visible: active
            sourceComponent: Rectangle {
                id: field
                property bool refused: false
                // Enter and leaving the field both end the edit; an unchanged value is not saved again
                function commit() {
                    const v = Model.fromText(root.row, input.text);
                    if (v !== null && JSON.stringify(v ?? null) === JSON.stringify(root.current ?? null)) {
                        refused = false;
                        return;
                    }
                    refused = v === null || !root.store.set(root.row.key, v);
                    if (!refused) input.text = Qt.binding(() => Model.toText(root.current));
                }
                width: root.row.kind === "list" ? 320 : 160
                height: Spacing.xxl + Spacing.sm
                radius: height / 2
                color: Colors.surfaceContainerHighest
                border.width: refused ? 2 : 0
                border.color: Colors.error
                Text {
                    anchors.left: input.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === "" && !input.activeFocus
                    text: root.row.placeholder
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.bodyMedium)
                }
                TextInput {
                    id: input
                    objectName: "settingField_" + root.row.key
                    anchors.fill: parent
                    anchors.leftMargin: Spacing.md
                    anchors.rightMargin: Spacing.md
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    text: Model.toText(root.current)
                    color: Colors.surfaceOn
                    selectionColor: Colors.primary
                    selectedTextColor: Colors.primaryOn
                    font: Type.font(Type.bodyMedium)
                    onTextEdited: field.refused = false
                    onEditingFinished: field.commit()
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
            active: root.row.kind === "action"
            visible: active
            sourceComponent: Button {
                objectName: "settingAction_" + root.row.key
                type: "tonal"
                size: "xs"
                text: root.row.button
                onClicked: root.runAction()
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
