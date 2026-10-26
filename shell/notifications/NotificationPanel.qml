pragma ComponentBehavior: Bound
// The notification list (D47), opened from the bell left of the status pill: a header with Do not disturb, the
// notifications newest first, grouped by app (an app's newest card, and "Show N more" to see the rest), as
// NotificationCards created only as they scroll into view (one that goes fades out and the rest close up), and
// Clear all, which sweeps the cards off to the side, the top one first, and only then reports the ones it
// took (`cleared(ids)`), so one that comes meanwhile stays. It grows in from the top right with the shared popup motion (D43) and closes when another window takes the keyboard,
// like Quick Settings (D41). Plain QtQuick on `notifications` (NotificationModel's data), so it tests offscreen.
import QtQuick
import qs.common
import qs.components
import "NotificationModel.js" as NotificationModel
import "NotificationRows.js" as NotificationRows

Rectangle {
    id: root

    property var notifications: []
    property bool dnd: false
    property bool shown: true
    property real now: Date.now()
    readonly property real maxListHeight: Spacing.xxxl * 10
    // The tallest it gets (a full list, Clear all), for the window: a fixed size, so the surface is not resized
    // on every frame while the list opens, closes up or grows (each resize is a compositor round trip, and the
    // motion stutters).
    readonly property real maxHeight: 2 * Spacing.md + header.height + maxListHeight + clearRow.height + 2 * column.spacing

    signal dndToggled(bool on)
    signal dismissed(int id)
    signal cleared(var ids)
    signal activated(int id)
    signal actionInvoked(int id, string action)
    signal replied(int id, string text)
    signal windowFocusLost()
    signal hidden()

    property var expanded: ({})             // {appName: true} for the groups showing all their notifications
    function toggleGroup(app) {
        const e = Object.assign({}, expanded);
        if (e[app] === true) delete e[app];
        else e[app] = true;
        expanded = e;
    }
    readonly property var byId: {
        const out = {};
        for (const n of notifications) out[n.id] = n;
        return out;
    }
    readonly property var groupRows: NotificationModel.groupRows(notifications, expanded)
    readonly property var rowByKey: {
        const out = {};
        for (const r of groupRows) out[r.key] = r;
        return out;
    }
    ListModel { id: rows }
    function syncRows() {
        // from the inputs, not groupRows: in a change handler that binding may not have caught up
        NotificationRows.sync(rows, NotificationModel.groupRows(notifications, expanded).map(r => r.key));
    }
    onNotificationsChanged: {
        syncRows();
        if (clearing && !clearSweep.running) Qt.callLater(endClear);
    }
    onExpandedChanged: syncRows()
    Component.onCompleted: syncRows()

    // Clear all: the rows it sweeps away (their keys) and the notifications it reports when the sweep is done
    property var clearingKeys: []
    property var clearingIds: []
    readonly property bool clearing: clearingKeys.length > 0
    function clearAll() {
        if (clearing || notifications.length === 0) return;
        const keys = [];
        for (let i = 0; i < rows.count; i++) keys.push(rows.get(i).key);
        clearingIds = notifications.map(n => n.id);
        clearingKeys = keys;
        clearSweep.restart();
    }
    // the last row starts a short4 after the first, and each takes a medium2 to go
    SequentialAnimation {
        id: clearSweep
        PauseAnimation { duration: Motion.duration(Motion.short4 + Motion.medium2) }
        ScriptAction { script: root.cleared(root.clearingIds) }
    }
    // Called once the list has changed after the sweep (onNotificationsChanged): a swept row that is still there
    // (it was not dismissed) comes back; the rows that went stay swept while they fade out.
    function endClear() {
        clearingKeys = [];
        clearingIds = [];
    }

    property bool windowActive: Window.active   // not readonly: the offscreen tests cannot move window focus
    property bool hadWindowFocus: false
    onWindowActiveChanged: {
        if (windowActive) hadWindowFocus = true;
        else if (hadWindowFocus) windowFocusLost();
    }

    implicitWidth: 360 + 2 * Spacing.md
    implicitHeight: column.height + 2 * Spacing.md
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.extraLarge
    color: Colors.surfaceContainer

    PopupMotion {
        target: root
        shown: root.shown
        origin: Item.TopRight
        onHidden: root.hidden()
    }

    Column {
        id: column
        x: Spacing.md
        y: Spacing.md
        width: root.width - 2 * Spacing.md
        spacing: Spacing.sm

        Item {
            id: header
            width: parent.width
            height: Spacing.xxl + Spacing.sm
            Text {
                x: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: Colors.surfaceOn
                font: Type.font(Type.titleMedium)
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                spacing: Spacing.sm
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Do not disturb"
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.labelLarge)
                }
                Switch {
                    objectName: "notificationDnd"
                    anchors.verticalCenter: parent.verticalCenter
                    controlled: true
                    checked: root.dnd
                    onToggled: on => root.dndToggled(on)
                }
            }
        }

        // The view keeps its full height and this clips it: a view that shrank at once would drop the card it is
        // removing out of view, and Qt then skips its remove transition (seen with Qt 6.12).
        Item {
            objectName: "notificationListClip"
            width: parent.width
            height: Math.min(list.contentHeight, root.maxListHeight)
            Behavior on height { EffectsNumber {} }
            visible: height > 0                 // it closes up after the last card has gone
            clip: true
            ListView {
                id: list
                objectName: "notificationList"
                width: parent.width
                height: root.maxListHeight
                spacing: Spacing.sm
                boundsBehavior: Flickable.StopAtBounds
                model: rows
                // at Motion.speed (D43), through the effects animations
                add: Transition { EffectsNumber { property: "opacity"; from: 0; to: 1 } }
                remove: Transition { EffectsNumber { property: "opacity"; to: 0 } }
                displaced: Transition { EffectsNumber { properties: "y" } }
                delegate: Loader {
                    id: rowItem
                    required property string key
                    property var kept: ({})              // what it showed, while it fades out
                    readonly property var row: root.rowByKey[key] ?? kept
                    onRowChanged: if (key in root.rowByKey) kept = root.rowByKey[key]
                    objectName: "notificationRow_" + key
                    width: list.width
                    sourceComponent: row.kind === "more" ? moreRow : cardRow
                    // Clear all sweeps it off to the side after a delay that grows down the view
                    readonly property bool swept: root.clearingKeys.indexOf(key) >= 0
                    property real sweep: 0
                    property real lag: 0
                    onSweptChanged: {
                        if (swept) {
                            lag = Math.max(0, Math.min(1, (y - list.contentY) / list.height));
                            sweepOut.restart();
                        } else if (key in root.rowByKey) {
                            sweepOut.stop();
                            sweep = 0;
                        }
                    }
                    transform: Translate { x: rowItem.sweep * (rowItem.width + Spacing.lg) }
                    // on the loaded item: the view's own add and remove transitions animate this Loader's opacity
                    Binding {
                        when: !!rowItem.item
                        target: rowItem.item
                        property: "opacity"
                        value: 1 - rowItem.sweep
                    }
                    SequentialAnimation {
                        id: sweepOut
                        PauseAnimation { duration: Math.round(Motion.duration(Motion.short4) * rowItem.lag) }
                        NumberAnimation {      // motion-speed: duration through Motion.duration() below
                            target: rowItem
                            property: "sweep"
                            to: 1
                            duration: Motion.duration(Motion.medium2)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.easing.emphasizedAccelerate
                        }
                    }
                    Component {
                        id: cardRow
                        NotificationCard {
                            id: card
                            property var keptNote: ({})
                            objectName: "notificationItem_" + rowItem.row.id
                            width: rowItem.width
                            notification: root.byId[rowItem.row.id] ?? keptNote
                            onNotificationChanged: if (rowItem.row.id in root.byId) keptNote = root.byId[rowItem.row.id]
                            now: root.now
                            onActivated: root.activated(rowItem.row.id)
                            onActionInvoked: action => root.actionInvoked(rowItem.row.id, action)
                            onDismissed: root.dismissed(rowItem.row.id)
                            onReplied: text => root.replied(rowItem.row.id, text)
                        }
                    }
                    Component {
                        id: moreRow
                        Item {
                            width: rowItem.width
                            height: more.height
                            Button {
                                id: more
                                objectName: "notificationMore_" + rowItem.row.app
                                anchors.right: parent.right
                                type: "text"
                                size: "xs"
                                iconName: rowItem.row.expanded ? "expand_less" : "expand_more"
                                text: rowItem.row.expanded ? "Show less"
                                      : "Show " + rowItem.row.count + " more from " + (rowItem.row.app || "this app")
                                onClicked: root.toggleGroup(rowItem.row.app)
                            }
                        }
                    }
                }
            }
        }

        Item {
            objectName: "notificationEmpty"
            opacity: root.notifications.length === 0 ? 1 : 0
            Behavior on opacity { EffectsNumber {} }
            visible: opacity > 0
            width: parent.width
            height: Spacing.xxxl * 2
            Column {
                anchors.centerIn: parent
                spacing: Spacing.sm
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.dnd ? "notifications_off" : "notifications"
                    size: Spacing.xl
                    color: Colors.surfaceVariantOn
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications"
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.bodyMedium)
                }
            }
        }

        Item {
            id: clearRow
            visible: root.notifications.length > 0
            width: parent.width
            height: clear.height
            Button {
                id: clear
                objectName: "notificationClearAll"
                anchors.right: parent.right
                type: "tonal"
                size: "s"
                text: "Clear all"
                enabled: !root.clearing
                onClicked: root.clearAll()
            }
        }
    }
}
