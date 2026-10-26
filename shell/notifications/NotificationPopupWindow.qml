// The notification popups' layer-shell surface: top right, under the status pill (it keeps clear of the pill's
// exclusive zone), above windows, as big as the cards so the rest of the screen takes clicks. No keyboard
// focus: a popup never takes typing away. The shell creates it in a LazyLoader only while there are popups
// (D31) and drops it once the last one has played its closing motion (`finished`).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: root

    readonly property bool done: popups.empty && NotificationService.popups.length === 0
    readonly property alias popups: popups

    signal finished()
    onDoneChanged: if (done) finished()

    anchors.top: true
    anchors.right: true
    margins.top: Spacing.sm
    margins.right: Spacing.sm
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.namespace: "rutile-notifications"
    WlrLayershell.layer: WlrLayer.Top
    implicitWidth: popups.implicitWidth
    implicitHeight: Math.max(1, popups.implicitHeight)
    color: "transparent"

    // ticks the cards' "5 min"
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: popups.now = Date.now()
    }

    NotificationPopups {
        id: popups
        width: root.implicitWidth
        popups: NotificationService.popups
        onActivated: id => NotificationService.popupDone(id)
        onActionInvoked: (id, action) => NotificationService.invoke(id, action)
        onDismissed: id => NotificationService.dismiss(id)
        onTimedOut: id => NotificationService.popupDone(id)
    }
}
