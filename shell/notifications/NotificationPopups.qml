pragma ComponentBehavior: Bound
// The notification popups (plan 2.8): a column of NotificationCards under the status pill, newest on top. Each
// grows in from the top right with the shared popup motion (D43) and plays it backwards when it leaves `popups`;
// the cards below slide up as its room closes. Plain QtQuick on `popups` ([NotificationModel data plus
// `timeout`]), so it tests offscreen; `empty` turns true once the last one has gone, for the window to unload.
// `fullHeight` is the room every card takes when fully open, for the window: it changes when a card comes and
// once a leaving card has gone, never during the motion, so the surface is not resized on every frame (each
// resize is a compositor round trip and the motion stutters). `area` is what is on screen, for the input mask.
import QtQuick
import qs.common
import qs.components

Item {
    id: root

    property var popups: []
    property real now: Date.now()
    readonly property bool empty: rows.count === 0
    property int replyingId: -1             // the card with its reply field open: the window needs the keyboard

    signal activated(int id)
    signal actionInvoked(int id, string action)
    signal dismissed(int id)
    signal timedOut(int id)
    signal replied(int id, string text)

    implicitWidth: 360
    implicitHeight: column.height
    property real fullHeight: 0
    readonly property Item area: column
    function measure() {
        let h = 0;
        for (let i = 0; i < repeater.count; i++)
            h += repeater.itemAt(i)?.room ?? 0;
        fullHeight = h;
    }

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
            id: repeater
            model: rows
            onItemAdded: Qt.callLater(root.measure)
            onItemRemoved: Qt.callLater(root.measure)
            Item {
                id: slot
                required property int nid
                required property bool leaving
                readonly property var info: root.byId[nid] ?? card.kept
                objectName: "notificationPopup_" + nid
                readonly property real room: card.implicitHeight + Spacing.sm
                onRoomChanged: Qt.callLater(root.measure)
                width: column.width
                // the room it takes opens and closes with its motion, so the cards below move smoothly
                height: room * motion.progress
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
                    onReplied: text => root.replied(slot.nid, text)
                    onReplyingChanged: {
                        if (replying) root.replyingId = slot.nid;
                        else if (root.replyingId === slot.nid) root.replyingId = -1;
                    }
                    Component.onDestruction: if (root.replyingId === slot.nid) root.replyingId = -1
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
