// Reserves space along a screen edge so the compositor lays windows out clear of the shell (layer shell's
// exclusive zone), without drawing anything: a 1 px transparent surface that lets every click through. The zone
// does not depend on the surface's size, so a 1 px strip reserves as much as a full bar would, for a few KB.
// The technique and shape follow DankMaterialShell's EdgeExclusion.qml (MIT); Caelestia does the same.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property string edge: "top"            // top | bottom | left | right
    property real size: 0                  // px reserved from that edge

    visible: size > 0
    color: "transparent"
    mask: Region {}
    implicitWidth: 1
    implicitHeight: 1
    exclusiveZone: size
    WlrLayershell.namespace: "rutile-exclusion"
    WlrLayershell.layer: WlrLayer.Top

    anchors.top: edge !== "bottom"
    anchors.bottom: edge !== "top"
    anchors.left: edge !== "right"
    anchors.right: edge !== "left"
}
