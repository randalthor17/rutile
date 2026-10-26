// The Quick Settings panel in its own layer-shell surface at the top right, under the status pill. The shell
// creates it in a LazyLoader only while open (D31) and destroys it on close. Escape closes it, and so does losing
// keyboard focus (a click into a window): it takes focus when it opens, at least on niri (D41). Closing plays the
// panel's closing motion first: close() starts it, and closeRequested asks the shell to unload once it ends.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

PanelWindow {
    id: root

    required property var backend

    signal closeRequested()

    // For `ipc call quicksettings state` (diagnostics and the Wayland smoke test).
    readonly property bool panelHasBackend: !!panel.backend
    readonly property bool brightnessShown: panel.brightnessShown
    readonly property bool closing: !panel.shown

    function close() { panel.shown = false; }
    function reopen() { panel.shown = true; }

    anchors.top: true
    anchors.right: true
    margins.top: 2 * Spacing.sm + Spacing.xl       // below the status pill
    margins.right: Spacing.sm
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "rutile-quicksettings"
    implicitWidth: panel.width
    // Tall enough for the power menu where it reaches below the panel; the mask keeps the empty part
    // click-through.
    implicitHeight: Math.max(panel.height, panel.menuBottom)
    mask: Region {
        item: panel
        Region { item: panel.powerMenu }
    }
    color: "transparent"

    QuickSettingsPanel {
        id: panel
        objectName: "quickSettingsPanel"
        backend: root.backend
        focus: true
        onWindowFocusLost: root.close()
        onPowerActionTaken: root.close()
        onHidden: root.closeRequested()
        Keys.onEscapePressed: root.close()
    }
}
