// A shelf button's tooltip (D106): a layer-shell surface just above the shelf, centred on the button, that takes no
// input. Loaded only while there is a tooltip (D31); when `shown` turns false it plays the popup motion, then says
// `gone` so its owner unloads it.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.components

PanelWindow {
    id: root

    property string text: ""
    property real centerX: 0                    // the button's middle, from the screen's left edge
    property real shelfHeight: 0
    property bool shown: true
    readonly property alias tooltip: tip

    signal gone()

    anchors.bottom: true
    anchors.left: true
    margins.bottom: shelfHeight + tip.spec.impl.anchorSpace
    margins.left: Math.max(Spacing.sm, Math.min((screen?.width ?? 0) - tip.width - Spacing.sm, centerX - tip.width / 2))
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    WlrLayershell.namespace: "rutile-shelf-tooltip"
    implicitWidth: tip.width
    implicitHeight: tip.height
    color: "transparent"
    mask: Region {}                             // the pointer goes through it

    Tooltip {
        id: tip
        text: root.text
        shown: root.shown
        origin: Item.Bottom
        onHidden: root.gone()
    }
}
