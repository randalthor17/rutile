// Shared behavior of Button and IconButton: container and outline colors from the type
// spec, a state layer, the pressed shape morph (a spatial spring on the corner radius),
// toggle state and keyboard activation. Children go into the content area.
import QtQuick
import qs.common

Item {
    id: root

    property var spec       // a size entry of ControlSpec.buttonSizes / iconButtonSizes
    property var colors     // a type entry of ControlSpec.buttonTypes / iconButtonTypes
    property string shape: "round"   // "round" or "square"
    property bool toggle: false
    property bool checked: false

    signal clicked()
    signal toggled(bool checked)

    default property alias content: contentArea.data

    readonly property bool pressed: layer.pressed
    readonly property bool hovered: layer.hovered
    readonly property bool selected: toggle && checked

    function role(name) {
        return name ? Colors[name] : "transparent";
    }
    // Shape tokens are px, or "full" meaning a pill: half the height.
    function px(v) {
        return v === "full" ? root.height / 2 : v;
    }

    readonly property real restRadius: {
        if (selected) return px(shape === "round" ? spec.shapeSelectedRound : spec.shapeSelectedSquare);
        return px(shape === "round" ? spec.shapeRound : spec.shapeSquare);
    }
    readonly property real pressedRadius: px(spec.shapePressed)
    readonly property real radiusNow: radiusSpring.value
    readonly property color containerNow: containerFade.value

    readonly property color containerColor: {
        if (!enabled)
            return colors.disabledContainer
                ? Qt.alpha(role(colors.disabledContainer), ControlSpec.stateOpacity.disabledContainer)
                : "transparent";
        return role(toggle ? (checked ? colors.selectedContainer : colors.unselectedContainer) : colors.container);
    }
    readonly property color contentColor: {
        if (!enabled)
            return Qt.alpha(role(colors.disabledContent), ControlSpec.stateOpacity.disabledContent);
        return role(toggle ? (checked ? colors.selectedContent : colors.unselectedContent) : colors.content);
    }
    readonly property bool outlined: !!colors.outline && !selected
    readonly property color outlineColor: enabled
        ? role(colors.outline)
        : Qt.alpha(role(colors.outline), ControlSpec.stateOpacity.disabledContainer)

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.onPressAction: activate()

    function activate() {
        if (!enabled) return;
        if (toggle) {
            checked = !checked;
            toggled(checked);
        }
        clicked();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activate();
            event.accepted = true;
        }
    }

    SpringColor {
        id: containerFade
        target: root.containerColor
    }

    Rectangle {
        anchors.fill: parent
        radius: radiusSpring.value
        color: containerFade.value
        border.width: root.outlined ? root.spec.outline : 0
        border.color: root.outlineColor
    }

    Item {
        id: contentArea
        anchors.fill: parent
    }

    StateLayer {
        id: layer
        anchors.fill: parent
        radius: radiusSpring.value
        stateColor: root.contentColor
        focused: root.activeFocus
        onClicked: root.activate()
    }

    Spring {
        id: radiusSpring
        target: root.pressed && root.enabled ? root.pressedRadius : root.restRadius
        stiffness: Motion.spring("spatial", "fast").stiffness
        dampingRatio: Motion.spring("spatial", "fast").dampingRatio
    }

    Component.onCompleted: radiusSpring.rest()
}
