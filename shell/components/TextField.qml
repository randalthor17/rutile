// An M3 text field (plan 1.5), filled or outlined, from the Compose tokens (ControlSpec.textFieldSpec): a label that
// rests in the field and floats to its top when it has focus or text, an optional leading icon, an optional trailing
// icon button (clear, show password...), supporting text under it, and an error state that colors label, outline and
// supporting text. Only the filled field's top corners are round. The outlined field's floating label sits on the
// outline over `backgroundColor`, which should be the color behind the field. `password` hides what is typed.
import QtQuick
import qs.common

Item {
    id: root

    property string type: "outlined"        // outlined | filled
    property alias text: textInput.text
    property string label: ""
    property string placeholderText: ""     // shown while empty and focused (or with no label)
    property string iconName: ""            // leading icon
    property string trailingIconName: ""    // a trailing icon button; `trailingClicked` when pressed
    property string supportingText: ""
    property bool error: false
    property bool password: false
    property color backgroundColor: Colors.surface
    readonly property alias input: textInput
    readonly property bool focused: textInput.activeFocus
    readonly property bool floating: focused || textInput.text !== "" || textInput.preeditText !== ""

    readonly property var spec: ControlSpec.textFieldSpec[type]
    readonly property bool outlined: type === "outlined"
    readonly property real fieldHeight: ControlSpec.textFieldSpec.outlined.containerHeight
    readonly property real padding: Spacing.lg
    readonly property real iconSize: spec.leadingIconSize

    // a token's color for the state, as Compose picks them: disabled, error (focused or not), focused, at rest.
    // `name` is the token's middle part: "Label", "Outline", "ActiveIndicator", "Input", "LeadingIcon"...
    function tokenColor(name) {
        const rest = name.charAt(0).toLowerCase() + name.slice(1) + "Color";
        if (!enabled) {
            const d = spec["disabled" + name + "Color"];
            return d ? Qt.alpha(Colors[d], spec["disabled" + name + "Opacity"] ?? 1) : Colors[spec[rest]];
        }
        const key = error ? (focused ? "errorFocus" : "error") + name + "Color" : focused ? "focus" + name + "Color" : rest;
        return Colors[spec[key] ?? spec[rest]];
    }
    readonly property color labelColor: tokenColor("Label")
    readonly property color supportingColor: tokenColor("Supporting")
    readonly property color indicatorColor: outlined ? tokenColor("Outline") : tokenColor("ActiveIndicator")
    readonly property real indicatorWidth: outlined ? (focused || error ? spec.focusOutlineWidth : spec.outlineWidth)
                                                   : (focused || error ? spec.focusActiveIndicatorHeight : spec.activeIndicatorHeight)

    signal accepted(string text)
    signal trailingClicked()

    implicitWidth: 280
    implicitHeight: fieldHeight + (supportingText !== "" ? Spacing.xs + supporting.implicitHeight : 0)
    activeFocusOnTab: true
    onActiveFocusChanged: if (activeFocus) textInput.forceActiveFocus()

    Accessible.role: Accessible.EditableText
    Accessible.name: label !== "" ? label : placeholderText

    // ---- the container ----
    Rectangle {
        id: box
        width: parent.width
        height: root.fieldHeight
        color: root.outlined ? "transparent" : (root.enabled ? Colors[root.spec.containerColor]
                                                              : Qt.alpha(Colors[root.spec.disabledContainerColor], root.spec.disabledContainerOpacity))
        topLeftRadius: root.spec.containerShape
        topRightRadius: root.spec.containerShape
        bottomLeftRadius: root.outlined ? root.spec.containerShape : 0
        bottomRightRadius: root.outlined ? root.spec.containerShape : 0
        border.width: root.outlined ? root.indicatorWidth : 0
        border.color: root.indicatorColor
        Behavior on border.width { EffectsNumber { speed: "fast" } }

        // the filled field's active indicator, along its bottom
        Rectangle {
            visible: !root.outlined
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.indicatorWidth
            color: root.indicatorColor
            Behavior on height { EffectsNumber { speed: "fast" } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onPressed: mouse => {
                textInput.forceActiveFocus();
                mouse.accepted = false;
            }
        }
    }

    Icon {
        id: leading
        visible: root.iconName !== ""
        anchors.left: box.left
        anchors.leftMargin: Spacing.md
        anchors.verticalCenter: box.verticalCenter
        name: root.iconName
        size: root.iconSize
        color: root.tokenColor("LeadingIcon")
    }

    IconButton {
        id: trailing
        objectName: "textFieldTrailing"
        visible: root.trailingIconName !== ""
        anchors.right: box.right
        anchors.rightMargin: Spacing.xs
        anchors.verticalCenter: box.verticalCenter
        iconName: root.trailingIconName
        onClicked: root.trailingClicked()
    }

    readonly property real textLeft: iconName !== "" ? Spacing.md + iconSize + Spacing.lg : padding
    readonly property real textRight: trailingIconName !== "" ? trailing.width + Spacing.xs : padding

    // ---- the label: in the field, or floated to its top ----
    Rectangle {
        // the outlined field's notch: the label's background over the outline
        visible: root.outlined && root.floating && root.label !== ""
        x: labelText.x - Spacing.xs
        y: 0
        width: labelText.width * labelText.scale + 2 * Spacing.xs
        height: root.indicatorWidth
        color: root.backgroundColor
    }
    Text {
        id: labelText
        objectName: "textFieldLabel"
        visible: root.label !== ""
        readonly property real restY: (root.fieldHeight - height) / 2
        readonly property real floatY: root.outlined ? -height / 2 : Spacing.sm - (height - height * scale) / 2
        x: root.textLeft - (root.outlined && root.floating ? root.textLeft - root.padding : 0)
        y: root.floating ? floatY : restY
        transformOrigin: Item.Left
        scale: root.floating ? Type.bodySmall.size / Type.bodyLarge.size : 1
        text: root.label
        color: root.labelColor
        font: Type.font(Type.bodyLarge)
        Behavior on y { EffectsNumber { speed: "fast" } }
        Behavior on x { EffectsNumber { speed: "fast" } }
        Behavior on scale { EffectsNumber { speed: "fast" } }
    }

    // ---- what is typed ----
    TextInput {
        id: textInput
        objectName: "textFieldInput"
        x: root.textLeft
        width: box.width - root.textLeft - root.textRight
        height: root.outlined || root.label === "" ? box.height : box.height - Spacing.lg
        y: root.outlined || root.label === "" ? 0 : Spacing.lg
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: root.tokenColor("Input")
        selectionColor: Qt.alpha(Colors.primary, 0.4)
        selectedTextColor: Colors.surfaceOn
        font: Type.font(Type.bodyLarge)
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        enabled: root.enabled
        onAccepted: root.accepted(text)

        Text {
            objectName: "textFieldPlaceholder"
            visible: textInput.text === "" && textInput.preeditText === "" && (root.label === "" || root.focused)
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholderText
            color: Colors[root.spec.inputPlaceholderColor]
            font: textInput.font
        }
    }

    Text {
        id: supporting
        objectName: "textFieldSupporting"
        visible: root.supportingText !== ""
        x: root.padding
        y: root.fieldHeight + Spacing.xs
        width: root.width - 2 * root.padding
        wrapMode: Text.Wrap
        text: root.supportingText
        color: root.supportingColor
        font: Type.font(Type.bodySmall)
    }
}
