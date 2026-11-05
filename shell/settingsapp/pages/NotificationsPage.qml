// Notifications (D110): Do not disturb, under the page's settings. A page view: the app sets `app`, `store` and
// `backend` (NotificationsBackend.qml, or the tests' fake), which has dnd and setDnd(b). The group is
// `setting_notifications.dnd`.
import QtQuick
import qs.common
import qs.components

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    ListItem {
        objectName: "setting_notifications.dnd"
        width: page.width
        tone: Colors.surfaceContainer
        iconName: page.backend?.dnd ? "do_not_disturb_on" : "do_not_disturb_off"
        text: "Do not disturb"
        supportingText: "No popups, except urgent ones; they still go to the list"
        onClicked: page.backend.setDnd(!page.backend.dnd)
        Switch {
            objectName: "dndSwitch"
            controlled: true
            checked: page.backend?.dnd ?? false
            onToggled: want => page.backend.setDnd(want)
        }
    }
}
