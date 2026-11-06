// Notifications kept across a restart (D131), on the test's private D-Bus: a saved list (and a broken entry in it)
// comes back as plain cards, newest first among the new ones; the list is saved again, readable only by the user;
// a dismissed restored one is gone from the file too; with notifications.keep off the file goes. busctl sends.
// env XDG_STATE_HOME=@WS@/keep-state
// env XDG_CONFIG_HOME=@WS@/keep-config
// env PATH=@WS@/bin:@PATH@
// env FAKE_PW_PLAY=@WS@/played.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root

    readonly property string file: Quickshell.env("XDG_STATE_HOME") + "/rutile/notifications.json"
    property int stage: 0
    property string onDisk: ""
    property string mode: ""
    QsTest { id: t }

    // the shell before: two saved, one not a notification
    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"', "sh", root.file, JSON.stringify([
            { liveId: 7, appName: "Mail", appIcon: "", image: "", summary: "Old mail", body: "from before", urgency: 1,
              critical: false, time: 2000 },
            { liveId: 3, appName: "Chat", appIcon: "", image: "image://qsimage/3", summary: "Older chat", body: "",
              urgency: 1, critical: false, time: 1000 },
            { nothing: true }
        ])]
        onExited: root.stage = 1
    }

    Process {
        id: sender
        command: ["busctl", "--user", "--", "call", "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                  "org.freedesktop.Notifications", "Notify", "susssasa{sv}i", "Mail", "0", "", "New mail", "now",
                  "2", "default", "Open", "0", "-1"]
    }
    Process {
        id: reader
        command: ["sh", "-c", 'stat -c %a "$1" 2>/dev/null || echo gone; printf "\\036"; cat "$1" 2>/dev/null', "sh", root.file]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\x1e");
                root.mode = parts[0].trim();
                root.onDisk = parts[1] ?? "";
                root.read();
            }
        }
    }
    signal read()
    function saved() {
        try {
            return JSON.parse(onDisk);
        } catch (e) {
            return null;
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: root.stage === 1 || root.stage === 2
        onTriggered: {
            const S = NotificationService;
            if (root.stage === 1) {
                t.compare(S.list.map(n => n.summary).join(), "Old mail,Older chat", "the saved ones, the broken one left out");
                t.compare(S.list.map(n => n.id).join(), "-1,-2", "ids of their own, below 0");
                t.compare(S.list[0].actions.length, 0, "no buttons: the sender is gone");
                t.verify(S.list[0].restored === true);
                t.compare(S.list[0].time, 2000, "when it came");
                t.compare(S.list[1].image, "", "an image held only in memory then is gone");
                sender.running = true;
                root.stage = 2;
            } else if (S.list.length === 3) {
                t.compare(S.list.map(n => n.summary).join(), "New mail,Old mail,Older chat", "the new one first");
                S.dismiss(-2);
                t.compare(S.list.map(n => n.summary).join(), "New mail,Old mail", "a restored one dismissed");
                S.invoke(-1, "default");       // nothing to do: no sender
                t.compare(S.list.length, 2);
                root.stage = 3;
                later.start();
            }
        }
    }
    Timer {
        id: later
        interval: 1800                  // past the save's moment
        onTriggered: reader.running = true
    }
    onRead: {
        const s = saved();
        if (stage === 3) {
            t.compare(mode, "600", "readable only by the user");
            t.compare(s ? s.map(n => n.summary).join() : onDisk, "New mail,Old mail", "saved again, the dismissed one gone");
            t.verify(s && s[0].liveId > 0 && s[1].liveId === -1, "the live one's id, for a reload");
            t.verify(s && s[0].actions === undefined, "no actions saved");
            Settings.set("notifications.keep", false);
            t.compare(NotificationService.list.map(n => n.summary).join(), "New mail", "keep off: the restored ones go");
            stage = 4;
            later.start();
        } else if (stage === 4) {
            t.compare(mode, "gone", "and the file");
            t.done();
        }
    }

    Timer {
        interval: 15000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage);
            t.done();
        }
    }
}
