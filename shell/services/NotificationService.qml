pragma Singleton
// The notification server (plan 2.8): Quickshell's NotificationServer on org.freedesktop.Notifications. Every
// notification is kept for the list (`list`, newest first, at most `maxKept`) and, unless Do not disturb is on
// (critical ones still do), pops up (`popups`, NotificationModel's data plus `timeout`). Both are plain data;
// the actions go back through dismiss(), invoke() and popupDone(). If another server holds the name (a second
// shell, another daemon), Quickshell waits and takes over when it is released. A notification that pops up plays a
// sound (the notifications.sound setting) with pw-play; while one plays, the next ones in a burst stay silent.
// While notifications.keep is on, the list is saved (NotificationModel.toSaved, D131) a moment after it changes,
// readable only by the user, and read back at start: those come back as plain cards (`restored`, ids below 0)
// until dismissed; one Quickshell kept across a reload is not shown twice.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../notifications/NotificationModel.js" as NotificationModel
import "Files.js" as Files

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
    // the saved ones, less those Quickshell kept alive across a reload (the same id and summary)
    readonly property var restoredShown: restored.filter(r => !tracked.some(n => n.id === r.liveId
                                                                           && NotificationModel.plain(n.summary) === r.summary))
    readonly property var list: tracked.map(n => data(n)).concat(restoredShown).sort((a, b) => b.time - a.time)
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
            actions: n.actions.map(a => ({ id: a.identifier, text: a.text })),
            time: root.times[n.id] ?? root.savedTime(n),
            reply: n.hasInlineReply ? (n.inlineReplyPlaceholder || "Reply") : "", transient: n.transient
        };
    }
    function find(id) {
        return tracked.find(n => n.id === id) ?? null;
    }

    // The user closed it: gone from the list too.
    function dismiss(id) {
        if (id < 0) restored = restored.filter(r => r.id !== id);
        else find(id)?.dismiss();
    }
    function dismissAll() {
        restored = [];
        tracked.slice().forEach(n => n.dismiss());
    }
    // An action (a button, or "default" for a click on the card); the sender closes it unless it is resident.
    // A restored one has no sender any more: nothing happens.
    function invoke(id, action) {
        const n = find(id);
        const a = n?.actions.find(x => x.identifier === action);
        popupDone(id);
        if (a) a.invoke();
    }
    // An inline reply goes to the sender; its popup is done.
    function reply(id, text) {
        const n = find(id);
        popupDone(id);
        if (n?.hasInlineReply) n.sendInlineReply(text);
    }
    // Its popup is done (timed out, or clicked without an action): it stays in the list unless it is transient.
    function popupDone(id) {
        popupIds = popupIds.filter(x => x !== id);
        const n = find(id);
        if (n?.transient) n.expire();
    }

    // The oldest go once there are more than maxKept, restored ones first.
    function trim() {
        const over = tracked.length + restored.length - maxKept;
        if (over > 0 && restored.length > 0)
            restored = restored.slice().sort((a, b) => b.time - a.time).slice(0, Math.max(0, restored.length - over));
        const kept = tracked.slice().sort((a, b) => (times[a.id] ?? 0) - (times[b.id] ?? 0));
        for (let i = 0; i < kept.length - maxKept; i++) kept[i].expire();
    }

    // ---- kept across a restart (D131) ----
    readonly property bool keep: Settings.value("notifications.keep") !== false
    readonly property string savedPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
        + "/rutile/notifications.json"
    property var restored: []
    property var saved: []              // as read at start, for the times of those kept across a reload
    property bool loaded: false
    function savedTime(n) {
        const s = saved.find(x => x.liveId === n.id && x.summary === NotificationModel.plain(n.summary));
        return s ? s.time : 0;
    }
    FileView {
        id: savedFile
        path: root.savedPath
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: {
        saved = NotificationModel.fromSaved(savedFile.text());
        if (keep) restored = saved.slice(0, maxKept);
        loaded = true;
    }
    onListChanged: if (loaded) saveSoon.restart()
    onKeepChanged: {
        if (!keep) restored = [];
        if (loaded) saveSoon.restart();
    }
    Timer {
        id: saveSoon
        interval: 1000
        onTriggered: {
            if (saver.running) return restart();
            saver.command = Files.applyCommand([root.keep
                ? { op: "write", path: root.savedPath, text: NotificationModel.toSaved(root.list, root.maxKept), mode: "600" }
                : { op: "remove", path: root.savedPath }]);
            saver.running = true;
        }
    }
    Process { id: saver }

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

    // Where sound themes are; the files tried for the last sound (diagnostics and tests).
    readonly property var dataDirs: NotificationModel.dataDirs(Quickshell.env("XDG_DATA_HOME"),
                                                                Quickshell.env("XDG_DATA_DIRS"), Quickshell.env("HOME"))
    property var lastSound: []
    function playSound(hints) {
        if (Settings.value("notifications.sound") !== true || player.running) return;
        const files = NotificationModel.soundFiles(hints, dataDirs);
        if (files.length === 0) return;
        lastSound = files;
        player.command = NotificationModel.playCommand(files);
        player.running = true;
    }
    Process { id: player }

    NotificationServer {
        id: server
        actionsSupported: true
        inlineReplySupported: true
        imageSupported: true
        persistenceSupported: true
        bodySupported: true
        onNotification: n => {
            n.tracked = true;
            const id = n.id;
            root.times = Object.assign({}, root.times, { [id]: Date.now() });
            n.closed.connect(() => root.forget(id));
            if (!n.lastGeneration && NotificationModel.pops(n.urgency, root.dnd)) {
                root.popupIds = root.popupIds.filter(x => x !== id).concat([id]);
                root.playSound(n.hints);
            }
            Qt.callLater(root.trim);         // the model adds it after this handler
        }
    }
}
