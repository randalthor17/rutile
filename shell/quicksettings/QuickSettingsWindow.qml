// The Quick Settings panel in its own layer-shell surface at the top right. The shell creates it in a
// LazyLoader only while open (D31) and destroys it on close. Escape closes it.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

PanelWindow {
    id: root

    signal closeRequested()

    anchors.top: true
    anchors.right: true
    margins.top: Spacing.sm
    margins.right: Spacing.sm
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "rutile-quicksettings"
    implicitWidth: panel.width
    implicitHeight: panel.height
    color: "transparent"

    QuickSettingsBackend { id: backend }

    QuickSettingsPanel {
        id: panel
        objectName: "quickSettingsPanel"
        backend: backend
        focus: true
        Keys.onEscapePressed: root.closeRequested()
    }
}
