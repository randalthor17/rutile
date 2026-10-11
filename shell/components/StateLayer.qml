// Hover, focus, pressed and dragged feedback: a translucent overlay of `stateColor` whose
// opacity chases the M3 state opacities with an effects spring (never overshoots).
// It also owns the MouseArea, so put it above the content it should react for.
import QtQuick
import qs.common

Item {
    id: root

    property color stateColor: Colors.surfaceOn
    property real radius: Shapes.none
    property bool focused: false
    property bool dragged: false

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    // Where the overlay opacity is heading (exposed for tests and for derived controls).
    readonly property real targetOpacity: {
        if (!enabled) return 0;
        if (dragged) return ControlSpec.stateOpacity.dragged;
        if (pressed) return ControlSpec.stateOpacity.pressed;
        if (hovered) return ControlSpec.stateOpacity.hover;
        if (focused) return ControlSpec.stateOpacity.focus;
        return 0;
    }
    readonly property real opacityNow: fade.value

    signal clicked()

    Spring {
        id: fade
        target: root.targetOpacity
        stiffness: Motion.spring("effects", "fast").stiffness
        dampingRatio: Motion.spring("effects", "fast").dampingRatio
        restDelta: 0.0005
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.stateColor
        opacity: fade.value
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        // Lint note: the Qt 6.4 linter cannot resolve Qt.CursorShape (a one-line MouseArea shows it).
        // qmllint disable type
        cursorShape: Qt.PointingHandCursor
        // qmllint enable type
        onClicked: root.clicked()
    }
}
