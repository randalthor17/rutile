// An M3 Expressive chip, 32 px tall. `assist` is an action (flat with an outline, or `elevated`);
// `filter` is selectable: it fills with secondaryContainer and shows a check when selected and it has
// no icon of its own. The check grows in and out with a spatial spring (the chip widens to make room), at
// Motion.speed (D43). Sizes, colors and spacing come from ControlSpec.chipSpec (Compose's chip tokens and the
// spacing Chip.kt hardcodes). Icons are only created when shown.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common

Item {
    id: root

    property string text: ""
    property string type: "assist"          // assist | filter
    property string iconName: ""            // leading icon
    property string trailingIconName: ""
    property bool elevated: false           // assist only: tonal container instead of an outline
    property bool selected: false           // filter only
    property bool controlled: false         // filter only: a click asks (`toggled(wanted)`), the owner sets `selected` (D33)

    signal clicked()
    signal toggled(bool selected)           // the state asked for; already shown unless `controlled`

    readonly property var spec: ControlSpec.chipSpec[type]
    readonly property var impl: ControlSpec.chipSpec.impl
    readonly property bool isFilter: type === "filter"
    readonly property bool on: isFilter && selected
    readonly property string leadingName: iconName !== "" ? iconName : (on ? "check" : "")
    // 0..1: how far the check has grown in (1 for a chip's own icon, which does not move; 0 with neither)
    readonly property real leadingShown: iconName !== "" ? 1 : checkSpring.value
    readonly property bool pressed: stateLayer.pressed
    readonly property bool hovered: stateLayer.hovered

    function alpha(roleName, opacity) {
        return Qt.alpha(Colors[roleName], opacity);
    }
    readonly property color containerColor: {
        if (isFilter) {
            if (!on) return "transparent";
            return enabled ? Colors[spec.flatSelectedContainerColor]
                           : alpha(spec.flatDisabledSelectedContainerColor, spec.flatDisabledSelectedContainerOpacity);
        }
        if (!elevated) return "transparent";
        return enabled ? Colors[spec.elevatedContainerColor]
                       : alpha(spec.elevatedDisabledContainerColor, spec.elevatedDisabledContainerOpacity);
    }
    readonly property color outlineColor: {
        if (isFilter) {
            if (on) return "transparent";
            return enabled ? Colors[spec.flatUnselectedOutlineColor]
                           : alpha(spec.flatDisabledUnselectedOutlineColor, spec.flatDisabledUnselectedOutlineOpacity);
        }
        return enabled ? Colors[spec.flatOutlineColor] : alpha(spec.flatDisabledOutlineColor, spec.flatDisabledOutlineOpacity);
    }
    readonly property real outlineWidth: isFilter ? (on ? spec.flatSelectedOutlineWidth : spec.flatUnselectedOutlineWidth)
                                                  : (elevated ? 0 : spec.flatOutlineWidth)
    readonly property color labelColor: {
        if (!enabled) return alpha(spec.disabledLabelTextColor, spec.disabledLabelTextOpacity);
        if (isFilter) return Colors[on ? spec.selectedLabelTextColor : spec.unselectedLabelTextColor];
        return Colors[spec.labelTextColor];
    }
    readonly property color leadingColor: {
        if (isFilter) {
            if (!enabled) return alpha(spec.disabledLeadingIconColor, spec.disabledLeadingIconOpacity);
            return Colors[on ? spec.selectedLeadingIconColor : spec.unselectedLeadingIconColor];
        }
        return enabled ? Colors[spec.iconColor] : alpha(spec.disabledIconColor, spec.disabledIconOpacity);
    }
    readonly property color trailingColor: {
        if (isFilter) {
            if (!enabled) return alpha(spec.disabledTrailingIconColor, spec.disabledTrailingIconOpacity);
            return Colors[on ? spec.selectedTrailingIconColor : spec.unselectedTrailingIconColor];
        }
        return leadingColor;
    }

    // Compose's ChipArrangement: content padding at both ends, `gap` between elements, and the compact
    // gap between a filter chip's icon and its label.
    readonly property real leadingGap: isFilter ? impl.gap + (impl.compactGap - impl.gap) * leadingShown : impl.gap
    readonly property real leadingWidth: spec.iconSize * leadingShown
    readonly property real trailingGap: trailingIconName === "" ? impl.gap : (isFilter ? impl.compactGap : impl.gap)

    implicitHeight: spec.containerHeight
    implicitWidth: impl.contentPadding + leadingWidth + leadingGap + label.implicitWidth
                   + trailingGap + (trailingIconName !== "" ? spec.iconSize : 0) + impl.contentPadding

    activeFocusOnTab: true
    Accessible.role: isFilter ? Accessible.CheckBox : Accessible.Button
    Accessible.name: text
    Accessible.checkable: isFilter
    Accessible.checked: on
    Accessible.onPressAction: activate()

    function activate() {
        if (!enabled) return;
        if (isFilter) {
            const wanted = !selected;
            if (!controlled) selected = wanted;
            toggled(wanted);
        }
        clicked();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activate();
            event.accepted = true;
        }
    }

    Spring {
        id: checkSpring
        target: root.leadingName === "check" ? 1 : 0
        stiffness: Motion.spring("spatial", "fast").stiffness
        dampingRatio: Motion.spring("spatial", "fast").dampingRatio
    }
    Component.onCompleted: checkSpring.rest()   // a chip that starts selected shows its check at once

    Rectangle {
        anchors.fill: parent
        radius: root.spec.containerShape
        color: root.containerColor
        Behavior on color { EffectsColor {} }
        border.width: root.outlineWidth
        border.color: root.outlineColor
    }

    Loader {
        id: leading
        objectName: "chipLeading"
        active: root.iconName !== "" || root.leadingShown > 0.01
        x: root.impl.contentPadding
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Icon {
            name: root.iconName !== "" ? root.iconName : "check"
            size: root.spec.iconSize
            color: root.leadingColor
            opacity: Math.min(1, root.leadingShown)
            scale: Math.max(0, root.leadingShown)
        }
    }

    Text {
        id: label
        objectName: "chipLabel"
        x: root.impl.contentPadding + root.leadingWidth + root.leadingGap
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: root.labelColor
        font: Type.font(Type[root.spec.labelTextFont])
    }

    Loader {
        active: root.trailingIconName !== ""
        x: root.width - root.impl.contentPadding - root.spec.iconSize
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Icon {
            name: root.trailingIconName
            size: root.spec.iconSize
            color: root.trailingColor
        }
    }

    StateLayer {
        id: stateLayer
        anchors.fill: parent
        radius: root.spec.containerShape
        stateColor: root.labelColor
        focused: root.activeFocus
        onClicked: root.activate()
    }
}
