// The status pill's layer-shell surface at the top right of one screen, with the notification bell left of it
// (D47) and the app indicators between them (plan 2.10, D61; only while there are some). Always present, so it is just the two; ScreenStatus.qml pairs it with the space it reserves.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: root

    required property var backend
    property bool open: false
    property bool notificationsOpen: false
    property var trayItems: []
    property string trayMenuId: ""              // the tray item whose menu is open on this screen
    readonly property alias bell: bell
    readonly property alias pill: pill
    readonly property alias tray: tray

    signal clicked()
    signal bellClicked()
    // a tray item's menu; right: from the window's right edge to the item's
    signal trayMenuRequested(var entry, real right)

    anchors.top: true
    anchors.right: true
    margins.top: Spacing.sm
    margins.right: Spacing.sm
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rutile-status"
    // Above windows, always visible; the space for it is reserved by an EdgeExclusion (ScreenStatus.qml).
    WlrLayershell.layer: WlrLayer.Top
    implicitWidth: row.width
    implicitHeight: pill.height
    color: "transparent"

    Row {
        id: row
        spacing: Spacing.xs
        NotificationBell {
            id: bell
            objectName: "notificationBell"
            count: NotificationService.list.length
            dnd: NotificationService.dnd
            open: root.notificationsOpen
            onClicked: root.bellClicked()
        }
        TrayPill {
            id: tray
            objectName: "trayPill"
            items: root.trayItems
            openId: root.trayMenuId
            onMenuRequested: (entry, right) => root.trayMenuRequested(entry, row.width - (tray.x + right))
        }
        StatusPill {
            id: pill
            backend: root.backend
            open: root.open
            onClicked: root.clicked()
        }
    }
}
