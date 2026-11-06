// The clipboard history picker's layer-shell surface (D119): centered above the shelf, as the launcher, with the
// keyboard while open. The shell creates it in a LazyLoader only while open (D31); close() plays the closing motion,
// then closeRequested asks the shell to unload it. It reads the history as it opens.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: root

    readonly property bool closing: !panel.shown
    readonly property alias panel: panel

    signal closeRequested()

    function close() { panel.shown = false; }
    function reopen() { panel.shown = true; }

    anchors.bottom: true
    margins.bottom: Spacing.sm
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    focusable: true
    WlrLayershell.namespace: "rutile-clipboard"
    implicitWidth: panel.width
    implicitHeight: panel.height
    color: "transparent"
    // what is behind the see-through panel, blurred by the compositor (D132)
    BackgroundEffect.blurRegion: Region { item: Panels.blurring ? panel : null; radius: panel.radius }

    Component.onCompleted: ClipboardService.list()

    ClipboardPanel {
        id: panel
        objectName: "clipboardPanel"
        entries: ClipboardService.entries
        reading: ClipboardService.reading
        onChosen: entry => {
            ClipboardService.copy(entry);
            root.close();
        }
        onRemoved: entry => ClipboardService.remove(entry)
        onWipeRequested: ClipboardService.wipe()
        onCloseRequested: root.close()
        onHidden: root.closeRequested()
    }
}
