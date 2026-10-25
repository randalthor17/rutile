// An M3 Expressive slider (horizontal): a 16 px track split by a 4x44 handle with a 6 px gap on
// each side, outer corners full and inner corners 2 px, a stop dot at the end, and tick dots when
// stepped. The handle narrows to 2 px while pressed or focused. Sizes and colors come from
// ControlSpec.sliderSpec, the drawing from Compose's Slider.kt.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common

Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0     // 0: continuous; otherwise values snap to from + n * stepSize

    signal moved(real value)      // the user changed the value (pointer or keyboard)

    readonly property var spec: ControlSpec.sliderSpec
    readonly property bool pressed: area.pressed && enabled
    readonly property bool hovered: area.containsMouse
    readonly property real position: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
    readonly property int stepCount: stepSize > 0 && to > from ? Math.round((to - from) / stepSize) : 0

    // Where the handle is heading (exposed for tests).
    readonly property real handleWidth: pressed || activeFocus ? spec.pressedHandleWidth : spec.handleWidth
    readonly property real handleWidthNow: widthSpring.value
    readonly property real trackStart: spec.handleWidth / 2
    readonly property real trackLength: Math.max(0, width - spec.handleWidth)
    readonly property real handleCenter: trackStart + position * trackLength

    function snapped(v) {
        v = Math.max(from, Math.min(to, v));
        if (stepCount > 0) v = from + Math.round((v - from) / stepSize) * stepSize;
        return Math.max(from, Math.min(to, v));
    }
    function setFromUser(v) {
        v = snapped(v);
        if (v === value) return;
        value = v;
        moved(v);
    }
    function valueAt(px) {
        return from + Math.max(0, Math.min(1, (px - trackStart) / Math.max(1, trackLength))) * (to - from);
    }

    implicitWidth: ControlSpec.progressSpec.impl.linearWidth
    implicitHeight: spec.handleHeight

    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.onIncreaseAction: setFromUser(value + keyStep())
    Accessible.onDecreaseAction: setFromUser(value - keyStep())

    // One step, or 1/100 of the range when continuous (as Compose).
    function keyStep() {
        return stepCount > 0 ? stepSize : (to - from) / 100;
    }
    Keys.onPressed: event => {
        if (!enabled) return;
        let handled = true;
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) setFromUser(value + keyStep());
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) setFromUser(value - keyStep());
        else if (event.key === Qt.Key_PageUp) setFromUser(value + (to - from) / 10);
        else if (event.key === Qt.Key_PageDown) setFromUser(value - (to - from) / 10);
        else if (event.key === Qt.Key_Home) setFromUser(from);
        else if (event.key === Qt.Key_End) setFromUser(to);
        else handled = false;
        event.accepted = handled;
    }

    function roleAt(roleName, opacity) {
        return Qt.alpha(Colors[roleName], opacity);
    }
    readonly property color activeColor: enabled ? Colors[spec.activeTrackColor]
        : roleAt(spec.disabledActiveTrackColor, spec.disabledActiveTrackOpacity)
    readonly property color inactiveColor: enabled ? Colors[spec.inactiveTrackColor]
        : roleAt(spec.disabledInactiveTrackColor, spec.disabledInactiveTrackOpacity)
    readonly property color handleColor: enabled ? Colors[spec.handleColor]
        : Qt.tint(Colors.surface, roleAt(spec.disabledHandleColor, spec.disabledHandleOpacity))

    Spring {
        id: widthSpring
        target: root.handleWidth
        stiffness: Motion.spring("spatial", "fast").stiffness
        dampingRatio: Motion.spring("spatial", "fast").dampingRatio
    }
    property color activeShown: root.activeColor
    Behavior on activeShown { EffectsColor {} }
    property color inactiveShown: root.inactiveColor
    Behavior on inactiveShown { EffectsColor {} }
    property color handleShown: root.handleColor
    Behavior on handleShown { EffectsColor {} }
    Component.onCompleted: widthSpring.rest()

    // Plain rectangles, not a Canvas: no per-instance pixel buffer and no JavaScript painting.
    Item {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        x: root.trackStart
        width: root.trackLength
        height: root.spec.inactiveTrackHeight

        readonly property real corner: height / 2
        readonly property real center: root.handleCenter - root.trackStart
        readonly property real gap: widthSpring.value / 2 + root.spec.impl.handleGap
        // A segment shorter than its rounded end is left out, as in Compose.
        readonly property bool showActive: center - gap > corner
        readonly property bool showInactive: center + gap < width - corner

        Rectangle {
            visible: track.showActive
            width: Math.max(0, track.center - track.gap)
            height: parent.height
            topLeftRadius: track.corner
            bottomLeftRadius: track.corner
            topRightRadius: root.spec.impl.trackInsideCorner
            bottomRightRadius: root.spec.impl.trackInsideCorner
            color: root.activeShown
        }
        Rectangle {
            visible: track.showInactive
            x: track.center + track.gap
            width: Math.max(0, track.width - x)
            height: parent.height
            topLeftRadius: root.spec.impl.trackInsideCorner
            bottomLeftRadius: root.spec.impl.trackInsideCorner
            topRightRadius: track.corner
            bottomRightRadius: track.corner
            color: root.inactiveShown
        }
        // Ticks sit where the handle stops: inactive-track color on the active side, active-track
        // color on the inactive side. Only stepped sliders create them.
        Repeater {
            model: Math.max(0, root.stepCount - 1)
            delegate: Rectangle {
                required property int index
                readonly property real cx: track.width * (index + 1) / root.stepCount
                visible: Math.abs(cx - track.center) > track.gap + width / 2
                width: root.spec.stopIndicatorSize
                height: width
                radius: width / 2
                x: cx - width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: cx < track.center ? root.inactiveShown : root.activeShown
            }
        }
        // The end stop shows with the inactive track.
        Rectangle {
            visible: track.showInactive
            width: root.spec.stopIndicatorSize
            height: width
            radius: width / 2
            x: track.width - track.corner - width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.activeShown
        }
    }

    Rectangle {
        id: handle
        width: widthSpring.value
        height: root.spec.handleHeight
        radius: width / 2
        x: root.handleCenter - width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.handleShown
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.forceActiveFocus();
            root.setFromUser(root.valueAt(mouse.x));
        }
        onPositionChanged: mouse => {
            if (pressed) root.setFromUser(root.valueAt(mouse.x));
        }
    }
}
