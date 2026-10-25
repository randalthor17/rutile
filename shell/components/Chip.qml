// An M3 Expressive chip, 32 px tall. `assist` is an action (flat with an outline, or `elevated`);
// `filter` is selectable: it fills with secondaryContainer and shows a check when selected and it has
// no icon of its own. Sizes, colors and spacing come from ControlSpec.chipSpec (Compose's chip tokens
// and the spacing Chip.kt hardcodes). Icons are only created when shown.
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

    signal clicked()
    signal toggled(bool selected)

    readonly property var spec: ControlSpec.chipSpec[type]
    readonly property var impl: ControlSpec.chipSpec.impl
    readonly property bool isFilter: type === "filter"
    readonly property bool on: isFilter && selected
    readonly property string leadingName: iconName !== "" ? iconName : (on ? "check" : "")
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
    readonly property real leadingGap: leadingName === "" ? impl.gap : (isFilter ? impl.compactGap : impl.gap)
    readonly property real trailingGap: trailingIconName === "" ? impl.gap : (isFilter ? impl.compactGap : impl.gap)

    implicitHeight: spec.containerHeight
    implicitWidth: impl.contentPadding + (leadingName !== "" ? spec.iconSize : 0) + leadingGap + label.implicitWidth
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
            selected = !selected;
            toggled(selected);
        }
        clicked();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activate();
            event.accepted = true;
        }
    }

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
        active: root.leadingName !== ""
        x: root.impl.contentPadding
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Icon {
            name: root.leadingName
            size: root.spec.iconSize
            color: root.leadingColor
        }
    }

    Text {
        id: label
        x: root.impl.contentPadding + (leading.active ? root.spec.iconSize : 0) + root.leadingGap
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
