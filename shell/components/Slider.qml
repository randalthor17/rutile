// An M3 Expressive slider (horizontal): a track split by a 4 px handle with a 6 px gap on each side,
// outer corners from the size and inner corners 2 px, a stop dot at the end, and tick dots when stepped.
// The handle narrows to 2 px while pressed or focused. `size` picks one of the five expressive sizes
// (xs is Compose's default slider; s, m, l, xl are taller, for Quick Settings and media). Sizes m and up
// take track icons: `startIcon` at the start of the active track, `endIcon` at the end of the inactive one,
// each shown only while its part of the track has room for it; the end icon replaces the stop dot.
// Under LayoutMirroring (right to left) the track fills from the right. Sizes and colors come from
// ControlSpec.sliderSpec, the drawing from Compose's Slider.kt; the sizes, the icon padding and the icon
// colors come from Material Components Android, which has tokens for them (Compose does not yet).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common

Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0     // 0: continuous; otherwise values snap to from + n * stepSize
    property string size: "xs"    // xs, s, m, l, xl
    property string startIcon: ""  // Material Symbols names; shown on sizes m, l and xl only
    property string endIcon: ""

    signal moved(real value)      // the user changed the value (pointer or keyboard)

    readonly property var spec: ControlSpec.sliderSpec
    readonly property var sizeSpec: spec.impl.sizes[size] ?? spec.impl.sizes.xs
    readonly property bool mirrored: LayoutMirroring.enabled
    readonly property bool pressed: area.pressed && enabled
    readonly property bool hovered: area.containsMouse
    readonly property real position: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
    readonly property int stepCount: stepSize > 0 && to > from ? Math.round((to - from) / stepSize) : 0

    // Where the handle is heading (exposed for tests). Positions are measured from the start edge,
    // which is the right edge when mirrored.
    readonly property real handleWidth: pressed || activeFocus ? spec.pressedHandleWidth : spec.handleWidth
    readonly property real handleWidthNow: widthSpring.value
    readonly property real trackStart: spec.handleWidth / 2
    readonly property real trackLength: Math.max(0, width - spec.handleWidth)
    readonly property real handleCenter: trackStart + position * trackLength

    // The track icons that are showing. An icon needs its size plus the padding on both sides of it in its
    // part of the track, or it is hidden (as in MDC).
    readonly property real iconRoom: sizeSpec.iconSize + 2 * spec.impl.trackIconPadding
    readonly property bool startIconShown: startIcon !== "" && sizeSpec.iconSize > 0 && track.showActive
        && track.activeLength >= iconRoom
    readonly property bool endIconShown: endIcon !== "" && sizeSpec.iconSize > 0 && track.showInactive
        && track.inactiveLength >= iconRoom

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
    // `px` is a pointer x in the slider's own coordinates.
    function valueAt(px) {
        const along = mirrored ? width - px : px;
        return from + Math.max(0, Math.min(1, (along - trackStart) / Math.max(1, trackLength))) * (to - from);
    }

    implicitWidth: ControlSpec.progressSpec.impl.linearWidth
    implicitHeight: sizeSpec.handleHeight

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
        // The arrow pointing toward the end of the track increases, so left does when mirrored.
        const forward = mirrored ? Qt.Key_Left : Qt.Key_Right;
        const back = mirrored ? Qt.Key_Right : Qt.Key_Left;
        let handled = true;
        if (event.key === forward || event.key === Qt.Key_Up) setFromUser(value + keyStep());
        else if (event.key === back || event.key === Qt.Key_Down) setFromUser(value - keyStep());
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
    readonly property color disabledIconColor: roleAt("surfaceOn", ControlSpec.stateOpacity.disabledContent)

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
    // The track sits centered, so only the parts inside it need mirroring.
    Item {
        id: track
        objectName: "sliderTrack"
        anchors.verticalCenter: parent.verticalCenter
        x: root.trackStart
        width: root.trackLength
        height: root.sizeSpec.trackHeight

        readonly property real corner: Math.min(root.sizeSpec.trackCorner, height / 2)
        readonly property real inside: root.spec.impl.trackInsideCorner
        readonly property real center: root.handleCenter - root.trackStart
        readonly property real gap: widthSpring.value / 2 + root.spec.impl.handleGap
        readonly property real activeLength: center - gap
        readonly property real inactiveLength: width - center - gap
        // The default (xs) slider leaves out a part shorter than its rounded end. The larger sizes shrink
        // the corners instead, as Compose's track with a corner size does; stepped sliders never shrink.
        readonly property bool shrinkCorners: root.size !== "xs" && root.stepCount === 0
        readonly property bool showActive: activeLength > (shrinkCorners ? 0 : corner)
        readonly property bool showInactive: inactiveLength > (shrinkCorners ? 0 : corner)

        // x of a box `w` wide that starts `along` px from the start edge.
        function visualX(along, w) {
            return root.mirrored ? width - along - w : along;
        }
        // Each part's outer end gets the size's corner, the end by the handle the 2 px one; when corners
        // shrink, both scale down to fit the part's length, as Compose's RoundRect does.
        function fit(length) {
            return shrinkCorners ? Math.min(1, Math.max(0, length) / (corner + inside)) : 1;
        }
        readonly property real activeOuter: corner * fit(activeLength)
        readonly property real activeInner: inside * fit(activeLength)
        readonly property real inactiveOuter: corner * fit(inactiveLength)
        readonly property real inactiveInner: inside * fit(inactiveLength)

        // Plain rectangles without properties of their own: custom properties give every instance its
        // own meta object, which measurably costs memory (docs/memory.md). The start edge is on the right
        // when mirrored.
        Rectangle {
            objectName: "sliderActive"
            visible: track.showActive
            width: Math.max(0, track.activeLength)
            height: track.height
            x: root.mirrored ? track.width - width : 0
            topLeftRadius: root.mirrored ? track.activeInner : track.activeOuter
            bottomLeftRadius: topLeftRadius
            topRightRadius: root.mirrored ? track.activeOuter : track.activeInner
            bottomRightRadius: topRightRadius
            color: root.activeShown
        }
        Rectangle {
            objectName: "sliderInactive"
            visible: track.showInactive
            width: Math.max(0, track.inactiveLength)
            height: track.height
            x: root.mirrored ? 0 : track.width - width
            topLeftRadius: root.mirrored ? track.inactiveOuter : track.inactiveInner
            bottomLeftRadius: topLeftRadius
            topRightRadius: root.mirrored ? track.inactiveInner : track.inactiveOuter
            bottomRightRadius: topRightRadius
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
                x: track.visualX(cx - width / 2, width)
                anchors.verticalCenter: parent.verticalCenter
                color: cx < track.center ? root.inactiveShown : root.activeShown
            }
        }
        // The end stop shows with the inactive track, unless the end icon takes its place.
        Rectangle {
            objectName: "sliderStop"
            visible: track.showInactive && !root.endIconShown
            width: root.spec.stopIndicatorSize
            height: width
            radius: width / 2
            x: track.visualX(track.width - track.corner - width / 2, width)
            anchors.verticalCenter: parent.verticalCenter
            color: root.activeShown
        }

        // Created only when an icon is set and the size has track icons; one Loader for both, since an
        // idle Loader costs about as much as an icon.
        Loader {
            active: (root.startIcon !== "" || root.endIcon !== "") && root.sizeSpec.iconSize > 0
            anchors.fill: parent
            sourceComponent: Item {
                Icon {
                    objectName: "sliderStartIcon"
                    name: root.startIcon
                    size: root.sizeSpec.iconSize
                    visible: root.startIconShown
                    x: track.visualX(root.spec.impl.trackIconPadding, size)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.enabled ? Colors[root.spec.impl.activeIconColor] : root.disabledIconColor
                }
                Icon {
                    objectName: "sliderEndIcon"
                    name: root.endIcon
                    size: root.sizeSpec.iconSize
                    visible: root.endIconShown
                    x: track.visualX(track.width - root.spec.impl.trackIconPadding - size, size)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.enabled ? Colors[root.spec.impl.inactiveIconColor] : root.disabledIconColor
                }
            }
        }
    }

    Rectangle {
        id: handle
        width: widthSpring.value
        height: root.sizeSpec.handleHeight
        radius: width / 2
        x: root.mirrored ? root.width - root.handleCenter - width / 2 : root.handleCenter - width / 2
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
