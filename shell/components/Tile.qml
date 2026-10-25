// A Quick Settings tile after Android 16's (SystemUI, Apache-2.0): 72 px tall. A large tile has a
// 56 px icon target, a label and a secondary label; `iconOnly` makes a square small tile. Inactive
// tiles are pills; active ones animate to 24 px corners (icon target 16 px). A `dualTarget` tile
// toggles from its icon and opens details from the rest (`clicked`); otherwise a click toggles.
// Values and per-state colors come from ControlSpec.tileSpec. The Googlebook look may differ; this
// follows Android until there are references (plan 0.2).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common

Item {
    id: root

    property string text: ""                // label
    property string secondaryText: ""       // state, e.g. "On" or a network name
    property string iconName: ""
    property bool active: false
    property bool available: true
    property bool dualTarget: false
    property bool iconOnly: false
    // Controlled: a toggle only asks (`toggled(wanted)`) and the owner sets `active` once the setting has
    // applied (D33). Every real tile is controlled; the default suits demos.
    property bool controlled: false

    signal clicked()                        // the tile body: opens details on a dual-target tile
    signal toggled(bool active)             // the state asked for; already shown unless `controlled`

    readonly property var spec: ControlSpec.tileSpec
    // Which of SystemUI's color sets applies (exposed for tests).
    readonly property string colorState: !available ? "unavailable"
                                       : (active ? (dualTarget ? "activeDual" : "active")
                                                 : (dualTarget ? "inactiveDual" : "inactive"))
    readonly property var colors: spec.states[colorState]
    readonly property bool pressed: bodyLayer.pressed || (iconLayer.item ? (iconLayer.item as StateLayer).pressed : false)
    readonly property real tileRadius: active && available ? spec.activeTileCornerRadius : spec.inactiveCornerRadius
    readonly property real iconRadius: active && available ? spec.activeIconCornerRadius : spec.inactiveCornerRadius
    readonly property color backgroundColor: Colors[colors.backgroundColor]

    implicitHeight: spec.tileHeight
    implicitWidth: iconOnly ? spec.tileHeight : 2 * spec.tileHeight + spec.tileArrangementPadding

    activeFocusOnTab: true
    Accessible.role: dualTarget ? Accessible.Button : Accessible.CheckBox
    Accessible.name: text
    Accessible.description: secondaryText
    Accessible.checkable: !dualTarget
    Accessible.checked: active
    Accessible.onPressAction: body()
    Accessible.onToggleAction: toggle()

    function toggle() {
        if (!enabled || !available) return;
        const wanted = !active;
        if (!controlled) active = wanted;
        toggled(wanted);
    }
    function body() {
        if (!enabled || !available) return;
        if (dualTarget) clicked();
        else toggle();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            body();
            event.accepted = true;
        }
    }

    Rectangle {
        id: tile
        anchors.fill: parent
        radius: root.tileRadius
        Behavior on radius { EffectsNumber {} }
        color: root.backgroundColor
        Behavior on color { EffectsColor {} }
    }

    StateLayer {
        id: bodyLayer
        anchors.fill: parent
        radius: tile.radius
        stateColor: Colors[root.colors.labelColor]
        focused: root.activeFocus
        onClicked: root.body()
    }

    // Large tile: the icon target, then the labels.
    Rectangle {
        id: iconTarget
        visible: !root.iconOnly
        x: root.spec.tilePadding
        anchors.verticalCenter: parent.verticalCenter
        width: root.spec.toggleTargetSize
        height: width
        radius: root.iconRadius
        Behavior on radius { EffectsNumber {} }
        color: Colors[root.colors.iconBackgroundColor]
        Behavior on color { EffectsColor {} }
    }

    // One icon for both layouts: centered in the tile when small, in the icon target when large.
    Icon {
        readonly property Item frame: root.iconOnly ? root : iconTarget
        x: frame.x * (root.iconOnly ? 0 : 1) + (frame.width - width) / 2
        y: (root.height - height) / 2
        name: root.iconName
        size: root.iconOnly ? root.spec.iconSize : root.spec.largeTileIconSize
        color: Colors[root.colors.iconColor]
    }

    // Only a dual-target tile's icon is its own button (toggle), with its own state layer.
    Loader {
        id: iconLayer
        active: root.dualTarget && !root.iconOnly
        anchors.fill: iconTarget
        sourceComponent: StateLayer {
            radius: iconTarget.radius
            stateColor: Colors[root.colors.iconColor]
            onClicked: root.toggle()
        }
    }

    Column {
        visible: !root.iconOnly
        x: iconTarget.x + iconTarget.width + root.spec.tileArrangementPadding
        width: Math.max(0, root.width - x - root.spec.tilePadding)
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: root.text
            elide: Text.ElideRight
            color: Colors[root.colors.labelColor]
            font: Type.font(Type[root.spec.labelFont])
        }
        Text {
            visible: root.secondaryText !== ""
            width: parent.width
            text: root.secondaryText
            elide: Text.ElideRight
            color: Colors[root.colors.secondaryLabelColor]
            font: Type.font(Type[root.spec.secondaryLabelFont])
        }
    }
}
