// An M3 Expressive slider (horizontal): a 16 px track split by a 4x44 handle with a 6 px gap on
// each side, outer corners full and inner corners 2 px, a stop dot at the end, and tick dots when
// stepped. The handle narrows to 2 px while pressed or focused. Sizes and colors come from
// ControlSpec.sliderSpec, the drawing from Compose's Slider.kt.
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
    SpringColor { id: activeFade; target: root.activeColor }
    SpringColor { id: inactiveFade; target: root.inactiveColor }
    SpringColor { id: handleFade; target: root.handleColor }
    Component.onCompleted: widthSpring.rest()

    Canvas {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        x: root.trackStart
        width: root.trackLength
        height: root.spec.inactiveTrackHeight

        // Repaint whenever anything drawn changes.
        readonly property var inputs: [root.handleCenter, widthSpring.value, activeFade.value, inactiveFade.value,
                                       root.stepCount, width, height]
        onInputsChanged: requestPaint()

        // A bar from x0 to x1 with corner radius r0 on the left and r1 on the right.
        function bar(ctx, x0, x1, r0, r1) {
            const h = height;
            r0 = Math.min(r0, h / 2, (x1 - x0) / 2);
            r1 = Math.min(r1, h / 2, (x1 - x0) / 2);
            ctx.beginPath();
            ctx.moveTo(x0 + r0, 0);
            ctx.lineTo(x1 - r1, 0);
            ctx.arcTo(x1, 0, x1, r1, r1);
            ctx.lineTo(x1, h - r1);
            ctx.arcTo(x1, h, x1 - r1, h, r1);
            ctx.lineTo(x0 + r0, h);
            ctx.arcTo(x0, h, x0, h - r0, r0);
            ctx.lineTo(x0, r0);
            ctx.arcTo(x0, 0, x0 + r0, 0, r0);
            ctx.closePath();
            ctx.fill();
        }
        function dot(ctx, cx, size) {
            ctx.beginPath();
            ctx.arc(cx, height / 2, size / 2, 0, 2 * Math.PI);
            ctx.fill();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const spec = root.spec;
            const corner = height / 2;
            const inside = spec.impl.trackInsideCorner;
            const center = root.handleCenter - root.trackStart;
            const gap = widthSpring.value / 2 + spec.impl.handleGap;
            // A segment shorter than its rounded end is left out, as in Compose.
            const showActive = center - gap > corner;
            const showInactive = center + gap < width - corner;
            if (showActive) {
                ctx.fillStyle = activeFade.value;
                bar(ctx, 0, center - gap, corner, inside);
            }
            if (showInactive) {
                ctx.fillStyle = inactiveFade.value;
                bar(ctx, center + gap, width, inside, corner);
            }
            // Ticks sit where the handle stops: inactive-track color on the active side,
            // active-track color on the inactive side. The end stop shows with the inactive track.
            const size = spec.stopIndicatorSize;
            for (let i = 1; i < root.stepCount; i++) {
                const cx = width * i / root.stepCount;
                if (Math.abs(cx - center) <= gap + size / 2) continue;
                ctx.fillStyle = cx < center ? inactiveFade.value : activeFade.value;
                dot(ctx, cx, size);
            }
            if (showInactive) {
                ctx.fillStyle = activeFade.value;
                dot(ctx, width - corner, size);
            }
        }
    }

    Rectangle {
        id: handle
        width: widthSpring.value
        height: root.spec.handleHeight
        radius: width / 2
        x: root.handleCenter - width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: handleFade.value
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        preventStealing: true
        // qmllint disable type
        cursorShape: Qt.PointingHandCursor
        // qmllint enable type
        onPressed: mouse => {
            root.forceActiveFocus();
            root.setFromUser(root.valueAt(mouse.x));
        }
        onPositionChanged: mouse => {
            if (pressed) root.setFromUser(root.valueAt(mouse.x));
        }
    }
}
