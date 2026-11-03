// A shelf button's right-click menu (D72): the layer-shell surface just above the shelf, centred on the button,
// with the shared menu (TrayMenuPanel: keyboard, the popup motion, closing on Escape or a click elsewhere). As the
// other panels it is loaded only while open (D31), and closing plays the motion before closeRequested asks the
// shell to unload it. `items` are ShelfApps.menuItems; the shell runs the choice (chosen).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.bar

PanelWindow {
    id: root

    property var items: []
    property real centerX: 0                    // the button's middle, from the screen's left edge
    property real shelfHeight: 0
    readonly property bool closing: !panel.shown
    readonly property alias panel: panel

    signal chosen(string id)
    signal closeRequested()

    function close() { panel.shown = false; }

    anchors.bottom: true
    anchors.left: true
    margins.bottom: shelfHeight + Spacing.sm
    margins.left: Math.max(Spacing.sm, Math.min((screen?.width ?? 0) - panel.width - Spacing.sm, centerX - panel.width / 2))
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "rutile-shelf-menu"
    implicitWidth: panel.width
    implicitHeight: panel.height
    color: "transparent"

    TrayMenuPanel {
        id: panel
        entries: root.items
        origin: Item.Bottom
        onChosen: id => {
            root.chosen(id);
            root.close();
        }
        onCloseRequested: root.close()
        onWindowFocusLost: root.close()
        onHidden: root.closeRequested()
    }
}
