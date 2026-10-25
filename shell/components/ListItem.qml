// An M3 Expressive list item: a headline, optional supporting text (two lines tall then), an optional
// leading icon, trailing supporting text, and a trailing slot for a control (put a Switch in it).
// Its corners morph with state (4 px at rest, 12 hovered, 16 pressed, focused or selected). In a
// segmented group (`position` first, middle or last) the group's outer corners stay at 16 px, as in
// Compose's ListItemDefaults.segmentedShapes. Values come from ControlSpec.listSpec.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common

Item {
    id: root

    property string text: ""                // headline
    property string supportingText: ""
    property string iconName: ""            // leading icon
    property string trailingText: ""
    property bool selected: false
    property string position: "single"      // single | first | middle | last (segmented groups)
    property color tone: Colors[spec.itemSegmentedContainerColor]
    default property alias trailing: trailingSlot.data

    signal clicked()

    readonly property var spec: ControlSpec.listSpec
    readonly property bool pressed: stateLayer.pressed
    readonly property bool hovered: stateLayer.hovered
    readonly property bool twoLine: supportingText !== ""

    // The shape the state asks for, and the fixed outer corners of a segmented group.
    readonly property real stateRadius: {
        const s = spec.impl.shapes;
        if (selected) return s.selected;
        if (pressed && enabled) return s.pressed;
        if (activeFocus) return s.focused;
        if (hovered && enabled) return s.hovered;
        return s.rest;
    }
    readonly property real radiusNow: radiusSpring.value
    readonly property real outer: spec.containerShape
    readonly property bool roundTop: position === "single" || position === "first"
    readonly property bool roundBottom: position === "single" || position === "last"

    function alpha(roleName, opacity) {
        return Qt.alpha(Colors[roleName], opacity);
    }
    readonly property color containerColor: {
        if (selected) return enabled ? Colors[spec.itemSelectedContainerColor]
                                     : alpha(spec.itemSelectedContainerColor, spec.itemSelectedDisabledContainerOpacity);
        return tone;
    }
    readonly property color labelColor: {
        if (!enabled) return alpha(spec.itemDisabledLabelTextColor, spec.itemDisabledLabelTextOpacity);
        return Colors[selected ? spec.itemSelectedLabelTextColor : spec.itemLabelTextColor];
    }
    readonly property color supportingColor: {
        if (!enabled) return alpha(spec.itemDisabledSupportingTextColor, spec.itemDisabledSupportingTextOpacity);
        return Colors[selected ? spec.itemSelectedSupportingTextColor : spec.itemSupportingTextColor];
    }
    readonly property color leadingColor: {
        if (!enabled) return alpha(spec.itemDisabledLeadingIconColor, spec.itemDisabledLeadingIconOpacity);
        return Colors[selected ? spec.itemSelectedLeadingIconColor : spec.itemLeadingIconColor];
    }
    readonly property color trailingTextColor: {
        if (!enabled) return alpha(spec.itemDisabledSupportingTextColor, spec.itemDisabledSupportingTextOpacity);
        return Colors[selected ? spec.itemSelectedTrailingSupportingTextColor : spec.itemTrailingSupportingTextColor];
    }

    implicitHeight: twoLine ? spec.itemTwoLineContainerHeight : spec.itemOneLineContainerHeight
    implicitWidth: spec.itemLeadingSpace + (iconName !== "" ? spec.itemLeadingIconSize + spec.itemBetweenSpace : 0)
                   + Math.max(headline.implicitWidth, supporting.implicitWidth)
                   + (trailingRow.implicitWidth > 0 ? spec.itemBetweenSpace + trailingRow.implicitWidth : 0)
                   + spec.itemTrailingSpace

    activeFocusOnTab: true
    Accessible.role: Accessible.ListItem
    Accessible.name: text
    Accessible.onPressAction: activate()

    function activate() {
        if (enabled) clicked();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activate();
            event.accepted = true;
        }
    }

    Spring {
        id: radiusSpring
        target: root.stateRadius
        stiffness: Motion.spring("spatial", "fast").stiffness
        dampingRatio: Motion.spring("spatial", "fast").dampingRatio
    }
    Component.onCompleted: radiusSpring.rest()

    Rectangle {
        id: container
        anchors.fill: parent
        topLeftRadius: root.roundTop ? root.outer : radiusSpring.value
        topRightRadius: root.roundTop ? root.outer : radiusSpring.value
        bottomLeftRadius: root.roundBottom ? root.outer : radiusSpring.value
        bottomRightRadius: root.roundBottom ? root.outer : radiusSpring.value
        color: root.containerColor
        Behavior on color { EffectsColor {} }
    }

    Loader {
        id: leading
        active: root.iconName !== ""
        x: root.spec.itemLeadingSpace
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Icon {
            name: root.iconName
            size: root.spec.itemLeadingIconSize
            color: root.leadingColor
        }
    }

    Column {
        x: root.spec.itemLeadingSpace + (leading.active ? root.spec.itemLeadingIconSize + root.spec.itemBetweenSpace : 0)
        width: Math.max(0, trailingRow.x - x - (trailingRow.implicitWidth > 0 ? root.spec.itemBetweenSpace : 0))
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: headline
            width: parent.width
            text: root.text
            elide: Text.ElideRight
            color: root.labelColor
            font: Type.font(Type[root.spec.itemLabelTextFont])
        }
        Text {
            id: supporting
            visible: root.twoLine
            width: parent.width
            text: root.supportingText
            elide: Text.ElideRight
            color: root.supportingColor
            font: Type.font(Type[root.spec.itemSupportingTextFont])
        }
    }

    // State layer below the trailing slot, so a control placed there gets its own input.
    StateLayer {
        id: stateLayer
        anchors.fill: parent
        topLeftRadius: container.topLeftRadius
        topRightRadius: container.topRightRadius
        bottomLeftRadius: container.bottomLeftRadius
        bottomRightRadius: container.bottomRightRadius
        stateColor: root.labelColor
        focused: root.activeFocus
        onClicked: root.activate()
    }

    Row {
        id: trailingRow
        x: root.width - root.spec.itemTrailingSpace - implicitWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spec.itemBetweenSpace

        Text {
            visible: root.trailingText !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.trailingText
            color: root.trailingTextColor
            font: Type.font(Type[root.spec.itemTrailingSupportingTextFont])
        }
        Item {
            id: trailingSlot
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
