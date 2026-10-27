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
    signal powerMenuRequested()

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
    implicitHeight: panel.height
    // From the geometry, not `item`: Quickshell measures an item with its scale and does not follow the scale as
    // it changes, so a mask taken while the popup motion grew the panel stayed at 0.85 of its size, and clicks
    // went through its left and bottom edges (seen with Quickshell 0.3.2).
    mask: Region {
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
    }
    color: "transparent"

    QuickSettingsPanel {
        id: panel
        objectName: "quickSettingsPanel"
        backend: root.backend
        focus: true
        onWindowFocusLost: root.close()
        onHidden: root.closeRequested()
        onPowerMenuRequested: root.powerMenuRequested()
        Keys.onEscapePressed: root.close()
    }
}
