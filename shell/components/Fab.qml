// An M3 Expressive floating action button (plan 1.5), from the Compose FAB tokens (ControlSpec.fabSpec): `size`
// small, baseline, medium or large; `variant` primary or secondary container; an `iconName`, and with `text` it is
// an extended FAB (icon and label) of the same height (not for small, which has none). `expanded` false shrinks an extended FAB back to its icon,
// animated. The label's type style follows Compose's ExtendedFloatingActionButton (titleMedium, titleLarge,
// headlineSmall for small, medium, large), which the token files leave out. No shadow yet (docs/components.md).
import QtQuick
import qs.common

Rectangle {
    id: root

    property string size: "baseline"        // small | baseline | medium | large
    property string variant: "primary"     // primary | secondary: the container color
    property string iconName: "add"
    property string text: ""
    property bool expanded: true
    readonly property bool extended: text !== ""
    readonly property var sizeSpec: ControlSpec.fabSpec.sizes[size]
    // the extended FAB of the same height: Compose's small extended FAB is 56, the baseline FAB's; a 40 px FAB has none
    readonly property var extendedSpec: ({ baseline: ControlSpec.fabSpec.extended.small, medium: ControlSpec.fabSpec.extended.medium,
                                           large: ControlSpec.fabSpec.extended.large })[size] ?? null
    readonly property var colorSpec: ControlSpec.fabSpec.colors[variant]
    readonly property var labelStyle: ({ small: Type.titleMedium, baseline: Type.titleMedium, medium: Type.titleLarge,
                                         large: Type.headlineSmall })[size]
    readonly property bool showLabel: extended && expanded && extendedSpec !== null
    readonly property real collapsedWidth: sizeSpec.containerWidth
    readonly property real expandedWidth: extendedSpec ? extendedSpec.leadingSpace + extendedSpec.iconSize
                                                         + extendedSpec.iconLabelSpace + label.implicitWidth
                                                         + extendedSpec.trailingSpace : collapsedWidth
    readonly property color contentColor: Colors[colorSpec.iconColor]

    signal clicked()

    implicitWidth: showLabel ? expandedWidth : collapsedWidth
    implicitHeight: extended && extendedSpec ? extendedSpec.containerHeight : sizeSpec.containerHeight
    width: implicitWidth
    height: implicitHeight
    radius: extended && extendedSpec ? extendedSpec.containerShape : sizeSpec.containerShape
    color: enabled ? Colors[colorSpec.containerColor] : Qt.alpha(Colors.surfaceOn, 0.12)
    clip: true
    activeFocusOnTab: true
    Behavior on implicitWidth { EffectsNumber {} }

    Accessible.role: Accessible.Button
    Accessible.name: text !== "" ? text : iconName
    Keys.onSpacePressed: root.clicked()
    Keys.onReturnPressed: root.clicked()

    Icon {
        id: icon
        x: root.showLabel ? root.extendedSpec.leadingSpace : (root.collapsedWidth - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        name: root.iconName
        size: root.extended && root.extendedSpec ? root.extendedSpec.iconSize : root.sizeSpec.iconSize
        color: root.enabled ? root.contentColor : Qt.alpha(Colors.surfaceOn, 0.38)
        Behavior on x { EffectsNumber {} }
    }
    Text {
        id: label
        objectName: "fabLabel"
        x: icon.x + icon.width + (root.extendedSpec?.iconLabelSpace ?? 0)
        anchors.verticalCenter: parent.verticalCenter
        visible: root.extended
        opacity: root.showLabel ? 1 : 0
        text: root.text
        color: icon.color
        font: Type.font(root.labelStyle)
        Behavior on opacity { EffectsNumber { speed: "fast" } }
    }
    StateLayer {
        anchors.fill: parent
        radius: root.radius
        enabled: root.enabled
        focused: root.activeFocus
        stateColor: root.contentColor
        onClicked: root.clicked()
    }
}
