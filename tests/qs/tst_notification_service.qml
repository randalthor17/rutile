// NotificationService (plan 2.8) on the test's private D-Bus (tools/qtws.py PrivateBus): what is kept, what pops
// up, Do not disturb, transient and critical notifications, replacing (in place, no new popup), actions and
// dismissing. busctl sends.
// env XDG_STATE_HOME=@WS@/state
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root

    property int stage: 0
    property var ids: ({})              // summary: id, as the server answered
    property string pendingName: ""

    QsTest { id: t }

    // Notify(app, replaces, icon, summary, body, actions, hints, timeout) over busctl; hints as busctl's words.
    function send(name, opts) {
        const o = opts || {};
        const actions = o.actions || [];
        const hints = o.hints || [];
        // "--": a timeout of -1 is not an option
        const args = ["busctl", "--user", "--", "call", "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                      "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
                      o.app || "Mail", String(o.replaces || 0), "", o.summary || name, o.body || "body " + name,
                      String(actions.length)].concat(actions)
                     .concat([String(hints.length / 3)]).concat(hints).concat([String(o.timeout ?? -1)]);
        pendingName = name;
        sender.command = args;
        sender.running = true;
    }
    Process {
        id: sender
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/u (\d+)/);
                if (m) root.ids = Object.assign({}, root.ids, { [root.pendingName]: parseInt(m[1]) });
                else t.verify(false, "busctl answered " + text);
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("QSTEST busctl: " + text) }
    }

    function popupIds() { return NotificationService.popups.map(n => n.id); }
    function listIds() { return NotificationService.list.map(n => n.id); }
    function item(id) { return NotificationService.list.find(n => n.id === id); }

    function step() {
        const S = NotificationService;
        switch (stage) {
        case 0:
            send("first", { actions: ["default", "Open", "reply", "Reply"], body: "<b>Hi</b> &amp; bye" });
            stage = 1;
            break;
        case 1:
            if (!("first" in ids) || !item(ids.first)) return;
            const first = item(ids.first);
            t.compare(first.appName, "Mail", "the app");
            t.compare(first.body, "Hi & bye", "markup dropped");
            t.compare(first.actions.map(a => a.id).join(), "default,reply", "the actions");
            t.verify(first.time > 0, "when it came");
            t.compare(popupIds().join(), String(ids.first), "it pops up");
            t.compare(S.popups[0].timeout, 6000, "the default timeout");
            S.setDnd(true);
            t.verify(S.dnd, "Do not disturb on");
            send("quiet");
            stage = 2;
            break;
        case 2:
            if (!("quiet" in ids) || !item(ids.quiet)) return;
            t.compare(popupIds().join(), String(ids.first), "Do not disturb: kept, no popup");
            t.compare(listIds()[0], ids.quiet, "newest first in the list");
            send("urgent", { hints: ["urgency", "y", "2"] });
            stage = 3;
            break;
        case 3:
            if (!("urgent" in ids) || !item(ids.urgent)) return;
            t.compare(popupIds().join(), ids.first + "," + ids.urgent, "critical pops up through Do not disturb");
            t.verify(item(ids.urgent).critical, "and is marked");
            t.compare(S.popups[1].timeout, 0, "and stays");
            S.setDnd(false);
            S.popupDone(ids.first);
            t.compare(popupIds().join(), String(ids.urgent), "a popup that is done goes");
            t.verify(!!item(ids.first), "but stays in the list");
            send("flash", { hints: ["transient", "b", "true"] });
            stage = 4;
            break;
        case 4:
            if (!("flash" in ids) || !item(ids.flash)) return;
            S.popupDone(ids.flash);
            stage = 5;
            break;
        case 5:
            if (item(ids.flash)) return;
            t.verify(true, "a transient one leaves the list with its popup");
            send("replaced", { replaces: ids.first, summary: "Changed", actions: ["reply", "Reply"] });
            stage = 6;
            break;
        case 6:
            if (!("replaced" in ids) || item(ids.first)?.summary !== "Changed") return;
            t.compare(ids.replaced, ids.first, "the same id");
            t.compare(listIds().filter(i => i === ids.first).length, 1, "once in the list");
            t.verify(popupIds().indexOf(ids.first) < 0, "updated in place: no new popup (progress updates would flood)");
            t.compare(item(ids.first).actions.map(a => a.id).join(), "reply", "with its new actions");
            S.invoke(ids.first, "reply");
            stage = 7;
            break;
        case 7:
            if (item(ids.first)) return;
            t.verify(popupIds().indexOf(ids.first) < 0, "an action closes it (not resident)");
            S.dismiss(ids.quiet);
            stage = 8;
            break;
        case 8:
            if (item(ids.quiet)) return;
            t.verify(!(ids.quiet in S.times), "a dismissed one is forgotten");
            send("stays", { actions: ["open", "Open"], hints: ["resident", "b", "true"] });
            stage = 9;
            break;
        case 9:
            if (!("stays" in ids) || !item(ids.stays)) return;
            S.invoke(ids.stays, "open");
            t.verify(popupIds().indexOf(ids.stays) < 0, "an action ends its popup");
            stage = 10;
            break;
        case 10:
            t.verify(!!item(ids.stays), "a resident one stays after an action");
            S.maxKept = S.list.length;
            send("over");
            stage = 11;
            break;
        case 11:
            if (!("over" in ids) || !item(ids.over)) return;
            t.compare(S.list.length, S.maxKept, "past the limit the oldest goes");
            t.verify(!item(ids.urgent), "the oldest was the critical one");
            S.maxKept = 50;
            send("chat", { actions: ["inline-reply", "Message"] });     // the action's text is the placeholder
            stage = 20;
            break;
        case 20:
            if (!("chat" in ids) || !item(ids.chat)) return;
            t.compare(item(ids.chat).reply, "Message", "an inline reply, with the sender's placeholder");
            S.reply(ids.chat, "hello");
            t.verify(popupIds().indexOf(ids.chat) < 0, "replying ends its popup");
            send("plain2");
            stage = 21;
            break;
        case 21:
            if (!("plain2" in ids) || !item(ids.plain2)) return;
            t.compare(item(ids.plain2).reply, "", "no inline reply offered: none");
            S.dismissAll();
            stage = 12;
            break;
        case 12:
            if (S.list.length > 0 || S.popups.length > 0) return;
            t.verify(true, "all dismissed, no popups left");
            t.compare(S.popupIds.length + Object.keys(S.times).length, 0, "nothing left behind");
            t.done();
            stage = 13;
            break;
        }
    }

    Timer { interval: 100; repeat: true; running: true; onTriggered: if (!sender.running) root.step() }
    Timer {
        interval: 15000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage + " ids " + JSON.stringify(root.ids)
                     + " list " + JSON.stringify(NotificationService.list.map(n => n.summary)));
            t.done();
        }
    }
}
