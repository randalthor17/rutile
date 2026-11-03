// An M3 card (plan 1.5), from the Compose card tokens (ControlSpec.cardSpec): `type` elevated, filled or outlined;
// whatever goes in it is laid out by the caller (the default slot). `interactive` makes the whole card a target:
// hover and press show the state layer and a click reports `clicked`. Elevation is the container color alone, as
// everywhere in the kit (no shadows yet, docs/components.md).
import QtQuick
import qs.common

Rectangle {
    id: root

    property string type: "filled"          // elevated | filled | outlined
    property bool interactive: false
    readonly property var spec: ControlSpec.cardSpec[type]
    readonly property bool hovered: stateLayer.hovered
    readonly property bool pressed: stateLayer.pressed
    default property alias content: body.data

    signal clicked()

    radius: spec.containerShape
    color: enabled ? Colors[spec.containerColor]
                   : (spec.disabledContainerColor ? Qt.alpha(Colors[spec.disabledContainerColor], spec.disabledContainerOpacity)
                                                  : Colors[spec.containerColor])
    border.width: spec.outlineWidth ?? 0
    border.color: {
        if (!spec.outlineColor) return "transparent";
        if (!enabled) return Qt.alpha(Colors[spec.disabledOutlineColor], spec.disabledOutlineOpacity);
        if (root.activeFocus) return Colors[spec.focusOutlineColor];
        if (pressed) return Colors[spec.pressedOutlineColor];
        if (hovered) return Colors[spec.hoverOutlineColor];
        return Colors[spec.outlineColor];
    }
    implicitWidth: body.childrenRect.width
    implicitHeight: body.childrenRect.height
    activeFocusOnTab: interactive

    Accessible.role: interactive ? Accessible.Button : Accessible.Pane
    Keys.onSpacePressed: if (interactive) root.clicked()
    Keys.onReturnPressed: if (interactive) root.clicked()

    Item {
        id: body
        anchors.fill: parent
    }
    StateLayer {
        id: stateLayer
        anchors.fill: parent
        visible: root.interactive
        enabled: root.interactive && root.enabled
        radius: root.radius
        focused: root.activeFocus
        stateColor: Colors.surfaceOn
        onClicked: root.clicked()
    }
}
