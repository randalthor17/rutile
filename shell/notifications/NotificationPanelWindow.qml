// The notification list's layer-shell surface at the top right, under the bell and the status pill. As Quick
// Settings' (D41): the shell creates it in a LazyLoader only while open (D31), it takes the keyboard on opening,
// Escape or a click into a window closes it, and closing plays the panel's motion before closeRequested asks
// the shell to unload it. The window keeps the panel's tallest size, and the mask lets clicks through below
// the panel.
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

    anchors.top: true
    anchors.right: true
    margins.top: 2 * Spacing.sm + Spacing.xl       // below the status pill
    margins.right: Spacing.sm
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "rutile-notification-list"
    implicitWidth: panel.width
    implicitHeight: panel.maxHeight
    mask: Region { item: panel }
    color: "transparent"

    // ticks the cards' "5 min"
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: panel.now = Date.now()
    }

    NotificationPanel {
        id: panel
        objectName: "notificationPanel"
        focus: true
        notifications: NotificationService.list
        dnd: NotificationService.dnd
        onDndToggled: on => NotificationService.setDnd(on)
        onDismissed: id => NotificationService.dismiss(id)
        onCleared: NotificationService.dismissAll()
        onActivated: id => {
            NotificationService.popupDone(id);
            root.close();
        }
        onActionInvoked: (id, action) => {
            NotificationService.invoke(id, action);
            root.close();
        }
        onReplied: (id, text) => NotificationService.reply(id, text)
        onWindowFocusLost: root.close()
        onHidden: root.closeRequested()
        Keys.onEscapePressed: root.close()
    }
}
