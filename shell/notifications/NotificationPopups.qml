pragma ComponentBehavior: Bound
// The notification popups (plan 2.8): a column of NotificationCards under the status pill, newest on top. Each
// grows in from the top right with the shared popup motion (D43) and plays it backwards when it leaves `popups`;
// the cards below slide up as its room closes. Plain QtQuick on `popups` ([NotificationModel data plus
// `timeout`]), so it tests offscreen; `empty` turns true once the last one has gone, for the window to unload.
import QtQuick
import qs.common
import qs.components

Item {
    id: root

    property var popups: []
    property real now: Date.now()
    readonly property bool empty: rows.count === 0

    signal activated(int id)
    signal actionInvoked(int id, string action)
    signal dismissed(int id)
    signal timedOut(int id)

    implicitWidth: 360
    implicitHeight: column.height

    // {id: data} for the cards, so a replaced notification updates its card in place
    readonly property var byId: {
        const out = {};
        for (const p of popups) out[p.id] = p;
        return out;
    }
    // Rows stay while their card leaves; a ListModel keeps the other cards (and their motion) as they are.
    ListModel { id: rows }
    function sync() {
        const ids = popups.map(p => p.id);         // not byId: its binding may not have caught up yet
        for (let i = rows.count - 1; i >= 0; i--)
            if (ids.indexOf(rows.get(i).nid) < 0) rows.setProperty(i, "leaving", true);
        for (const p of popups) {
            let found = false;
            for (let i = 0; i < rows.count; i++)
                if (rows.get(i).nid === p.id) {
                    found = true;
                    if (rows.get(i).leaving) rows.setProperty(i, "leaving", false);   // back before it had gone
                }
            if (!found) rows.insert(0, { nid: p.id, leaving: false });
        }
    }
    onPopupsChanged: sync()
    Component.onCompleted: sync()
    function remove(nid) {
        for (let i = 0; i < rows.count; i++)
            if (rows.get(i).nid === nid) {
                rows.remove(i);
                return;
            }
    }

    Column {
        id: column
        width: root.width
        Repeater {
            model: rows
            Item {
                id: slot
                required property int nid
                required property bool leaving
                readonly property var info: root.byId[nid] ?? card.kept
                objectName: "notificationPopup_" + nid
                width: column.width
                // the room it takes opens and closes with its motion, so the cards below move smoothly
                height: (card.implicitHeight + Spacing.sm) * motion.progress
                NotificationCard {
                    id: card
                    property var kept: ({})          // what it showed, while it leaves
                    width: parent.width
                    notification: slot.info
                    onNotificationChanged: if (slot.nid in root.byId) kept = root.byId[slot.nid]
                    timeout: slot.leaving ? 0 : (slot.info.timeout ?? 0)
                    now: root.now
                    onActivated: root.activated(slot.nid)
                    onActionInvoked: action => root.actionInvoked(slot.nid, action)
                    onDismissed: root.dismissed(slot.nid)
                    onTimedOut: root.timedOut(slot.nid)
                }
                PopupMotion {
                    id: motion
                    target: card
                    shown: !slot.leaving
                    origin: Item.TopRight
                    onHidden: Qt.callLater(root.remove, slot.nid)    // not from inside the row it removes
                }
            }
        }
    }
}
