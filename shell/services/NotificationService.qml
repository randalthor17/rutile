pragma Singleton
// The notification server (plan 2.8): Quickshell's NotificationServer on org.freedesktop.Notifications. Every
// notification is kept for the list (`list`, newest first, at most `maxKept`) and, unless Do not disturb is on
// (critical ones still do), pops up (`popups`, NotificationModel's data plus `timeout`). Both are plain data;
// the actions go back through dismiss(), invoke() and popupDone(). If another server holds the name (a second
// shell, another daemon), Quickshell waits and takes over when it is released.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../notifications/NotificationModel.js" as NotificationModel

Singleton {
    id: root

    property int maxKept: 50                // the oldest go past this (a test lowers it)
    // Do not disturb, remembered in state.json (D45)
    readonly property bool dnd: Settings.stateValue("notifications.dnd", false) === true
    function setDnd(on) {
        Settings.setState("notifications.dnd", on);
    }

    property var times: ({})                // id: when it came, ms (a replacement updates it in place)
    property var popupIds: []               // waiting to pop up or showing, oldest first

    readonly property var tracked: server.trackedNotifications.values
    readonly property var list: tracked.map(n => data(n)).sort((a, b) => b.time - a.time)
    readonly property var popups: NotificationModel.visiblePopups(popupIds)
        .map(id => tracked.find(n => n.id === id)).filter(n => !!n)
        .map(n => Object.assign(data(n), { timeout: NotificationModel.timeout(n.expireTimeout, n.urgency) }))

    function iconUrl(icon) {
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.indexOf("://") > 0) return icon;
        return Quickshell.iconPath(icon, true);
    }
    function data(n) {
        return {
            id: n.id, appName: n.appName, appIcon: iconUrl(n.appIcon), image: iconUrl(n.image),
            summary: NotificationModel.plain(n.summary), body: NotificationModel.plain(n.body), urgency: n.urgency,
            critical: n.urgency === NotificationUrgency.Critical,
            actions: n.actions.map(a => ({ id: a.identifier, text: a.text })), time: root.times[n.id] ?? 0
        };
    }
    function find(id) {
        return tracked.find(n => n.id === id) ?? null;
    }

    // The user closed it: gone from the list too.
    function dismiss(id) {
        find(id)?.dismiss();
    }
    function dismissAll() {
        tracked.slice().forEach(n => n.dismiss());
    }
    // An action (a button, or "default" for a click on the card); the sender closes it unless it is resident.
    function invoke(id, action) {
        const n = find(id);
        const a = n?.actions.find(x => x.identifier === action);
        popupDone(id);
        if (a) a.invoke();
    }
    // Its popup is done (timed out, or clicked without an action): it stays in the list unless it is transient.
    function popupDone(id) {
        popupIds = popupIds.filter(x => x !== id);
        const n = find(id);
        if (n?.transient) n.expire();
    }

    // The oldest go once there are more than maxKept.
    function trim() {
        const kept = tracked.slice().sort((a, b) => (times[a.id] ?? 0) - (times[b.id] ?? 0));
        for (let i = 0; i < kept.length - maxKept; i++) kept[i].expire();
    }

    // Every popup is done (the list has opened, and shows them).
    function endPopups() {
        popupIds.slice().forEach(id => popupDone(id));
    }

    function forget(id) {
        popupIds = popupIds.filter(x => x !== id);
        const t = Object.assign({}, times);
        delete t[id];
        times = t;
    }

    NotificationServer {
        id: server
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        bodySupported: true
        onNotification: n => {
            n.tracked = true;
            const id = n.id;
            root.times = Object.assign({}, root.times, { [id]: Date.now() });
            n.closed.connect(() => root.forget(id));
            if (!n.lastGeneration && NotificationModel.pops(n.urgency, root.dnd))
                root.popupIds = root.popupIds.filter(x => x !== id).concat([id]);
            Qt.callLater(root.trim);         // the model adds it after this handler
        }
    }
}
