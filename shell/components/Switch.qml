// An M3 Expressive switch: a 52x32 track and a handle that grows from 16 (off) to 24 (on, or
// with an icon) and to 28 while pressed. Sizes and colors come from ControlSpec.switchSpec;
// the motion follows Compose's Switch.kt: a fast spatial spring, snapping while pressed.
import QtQuick
import qs.common

Item {
    id: root

    property bool checked: false
    property string checkedIcon: ""      // Material Symbols name shown in the handle when on
    property string uncheckedIcon: ""    // ... and when off; either one makes the handle 24 px

    signal toggled(bool checked)

    readonly property var spec: ControlSpec.switchSpec
    readonly property bool pressed: area.pressed && enabled
    readonly property bool hovered: area.containsMouse
    readonly property string iconName: checked ? checkedIcon : uncheckedIcon
    readonly property bool hasIcon: checkedIcon !== "" || uncheckedIcon !== ""

    // Where the handle is heading (exposed for tests): its diameter and left edge in px.
    readonly property real handleSize: {
        if (pressed) return spec.pressedHandleWidth;
        return hasIcon || checked ? spec.selectedHandleWidth : spec.unselectedHandleWidth;
    }
    readonly property real handleX: {
        const maxX = spec.trackWidth - spec.selectedHandleWidth - (spec.trackHeight - spec.selectedHandleWidth) / 2;
        if (pressed) return checked ? maxX - spec.trackOutlineWidth : spec.trackOutlineWidth;
        return checked ? maxX : (spec.trackHeight - handleSize) / 2;
    }
    readonly property real handleSizeNow: sizeSpring.value
    readonly property real handleXNow: xSpring.value

    // Disabled colors are the role at the token opacity, composited over the surface (as Compose does).
    function disabled(roleName, opacity) {
        return Qt.tint(Colors.surface, Qt.alpha(Colors[roleName], opacity));
    }
    readonly property bool active: hovered || pressed || activeFocus
    readonly property color trackColor: {
        if (!enabled)
            return checked ? disabled(spec.disabledSelectedTrackColor, spec.disabledTrackOpacity)
                           : disabled(spec.disabledUnselectedTrackColor, spec.disabledTrackOpacity);
        return Colors[checked ? spec.selectedTrackColor : spec.unselectedTrackColor];
    }
    readonly property color outlineColor: {
        if (checked) return "transparent";
        if (!enabled) return disabled(spec.disabledUnselectedTrackOutlineColor, spec.disabledTrackOpacity);
        return Colors[spec.unselectedTrackOutlineColor];
    }
    readonly property color handleColor: {
        if (!enabled)
            return checked ? disabled(spec.disabledSelectedHandleColor, spec.disabledSelectedHandleOpacity)
                           : disabled(spec.disabledUnselectedHandleColor, spec.disabledUnselectedHandleOpacity);
        if (checked) return Colors[active ? spec.selectedPressedHandleColor : spec.selectedHandleColor];
        return Colors[active ? spec.unselectedPressedHandleColor : spec.unselectedHandleColor];
    }
    readonly property color iconColor: {
        if (!enabled)
            return checked ? disabled(spec.disabledSelectedIconColor, spec.disabledSelectedIconOpacity)
                           : disabled(spec.disabledUnselectedIconColor, spec.disabledUnselectedIconOpacity);
        return Colors[checked ? spec.selectedIconColor : spec.unselectedIconColor];
    }

    implicitWidth: spec.trackWidth
    implicitHeight: spec.trackHeight

    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onPressAction: toggle()
    Accessible.onToggleAction: toggle()

    function toggle() {
        if (!enabled) return;
        checked = !checked;
        toggled(checked);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            toggle();
            event.accepted = true;
        }
    }

    // Targets are assigned, not bound: a press snaps the handle (Compose's SnapSpec), and
    // Spring.snap() would break a binding.
    function follow() {
        if (pressed) {
            sizeSpring.snap(handleSize);
            xSpring.snap(handleX);
        } else {
            sizeSpring.target = handleSize;
            xSpring.target = handleX;
        }
    }
    onHandleSizeChanged: follow()
    onHandleXChanged: follow()
    Component.onCompleted: {
        sizeSpring.snap(handleSize);
        xSpring.snap(handleX);
    }

    Spring {
        id: sizeSpring
        stiffness: Motion.spring("spatial", "fast").stiffness
        dampingRatio: Motion.spring("spatial", "fast").dampingRatio
    }
    Spring {
        id: xSpring
        stiffness: Motion.spring("spatial", "fast").stiffness
        dampingRatio: Motion.spring("spatial", "fast").dampingRatio
    }
    SpringColor { id: trackFade; target: root.trackColor }
    SpringColor { id: outlineFade; target: root.outlineColor }
    SpringColor { id: handleFade; target: root.handleColor }

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: root.spec.trackWidth
        height: root.spec.trackHeight
        radius: height / 2
        color: trackFade.value
        border.width: root.spec.trackOutlineWidth
        border.color: outlineFade.value
    }

    StateLayer {
        id: layer
        width: root.spec.stateLayerSize
        height: width
        radius: width / 2
        x: track.x + xSpring.value + sizeSpring.value / 2 - width / 2
        y: track.y + (track.height - height) / 2
        input: area
        focused: root.activeFocus
        stateColor: root.checked ? Colors.primary : Colors.surfaceOn
    }

    Rectangle {
        id: handle
        width: sizeSpring.value
        height: width
        radius: width / 2
        x: track.x + xSpring.value
        y: track.y + (track.height - height) / 2
        color: handleFade.value

        Icon {
            anchors.centerIn: parent
            visible: root.iconName !== ""
            name: root.iconName
            size: root.spec.selectedIconSize
            color: root.iconColor
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        // qmllint disable type
        cursorShape: Qt.PointingHandCursor
        // qmllint enable type
        onClicked: root.toggle()
    }
}
