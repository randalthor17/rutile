// The Notifications page's backend (NotificationsPage.qml has the interface, D110): Do not disturb, which is the
// shell's state (state.json, as the bell's and Quick Settings' switch), not a setting.
import QtQuick
import qs.services

Item {
    readonly property bool dnd: NotificationService.dnd
    function setDnd(on) { NotificationService.setDnd(on); }
}
