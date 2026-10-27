// The power menu's layer-shell surface (plan 2.8): the whole screen, on the overlay layer above everything, with the
// desktop behind it blurred by the compositor (BackgroundEffect, ext-background-effect-v1; niri 26.04 has it). It
// takes the keyboard while open. The shell creates it in a LazyLoader only while open (D31): close() or a choice
// plays the closing motion, then `finished(id)` gives the action ("" for none) and the shell unloads it and acts,
// so a lock screen or a shutdown never shows the menu.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    readonly property alias overlay: overlay
    readonly property bool closing: !overlay.shown
    property string pending: ""

    signal finished(string id)

    function close() { overlay.shown = false; }
    function reopen() {
        pending = "";
        overlay.shown = true;
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rutile-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    BackgroundEffect.blurRegion: Region { item: root.contentItem }

    PowerOverlay {
        id: overlay
        anchors.fill: parent
        onChosen: id => root.pending = id
        onHidden: root.finished(root.pending)
    }
}
