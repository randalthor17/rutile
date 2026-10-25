// Hover, focus, pressed and dragged feedback: a translucent overlay of `stateColor` whose
// opacity chases the M3 state opacities with an effects spring (never overshoots; a NumberAnimation
// on the spring's curve, see EffectsNumber).
// It also owns the MouseArea, so put it above the content it should react for. A control whose
// pointer area is larger than its overlay (the switch's circle) sets `input` to its own MouseArea.
import QtQuick
import qs.common

Item {
    id: root

    property color stateColor: Colors.surfaceOn
    property real radius: Shapes.none
    // Per-corner radii, for containers whose corners differ (segmented list items).
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomLeftRadius: radius
    property real bottomRightRadius: radius
    property bool focused: false
    property bool dragged: false
    property MouseArea input: mouse

    readonly property bool hovered: input.containsMouse
    readonly property bool pressed: input.pressed

    // Where the overlay opacity is heading (exposed for tests and for derived controls).
    readonly property real targetOpacity: {
        if (!enabled) return 0;
        if (dragged) return ControlSpec.stateOpacity.dragged;
        if (pressed) return ControlSpec.stateOpacity.pressed;
        if (hovered) return ControlSpec.stateOpacity.hover;
        if (focused) return ControlSpec.stateOpacity.focus;
        return 0;
    }
    readonly property real opacityNow: overlay.opacity

    signal clicked()

    Rectangle {
        id: overlay
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        color: root.stateColor
        opacity: root.targetOpacity
        visible: opacity > 0
        Behavior on opacity { EffectsNumber { speed: "fast" } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled && root.input === mouse
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
