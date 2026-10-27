// The notification sound (plan 2.8) on the test's private D-Bus: a notification that pops up plays the theme's
// message sound through pw-play (the fake in bin/, which logs instead of playing), or the sender's sound-name or
// sound-file; suppress-sound, Do not disturb (unless critical) and the notifications.sound setting keep it silent,
// and a burst plays once.
// env XDG_STATE_HOME=@WS@/state
// env PATH=@WS@/bin:@PATH@
// env FAKE_PW_PLAY=@WS@/played.log
// env XDG_DATA_HOME=@WS@/no-data-home
// env XDG_DATA_DIRS=@WS@/apps
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root

    property int stage: 0
    property int sent: 0                // notifications busctl has delivered
    property var played: []             // the fake's log, one call per line
    // the fixture's sound theme (Quickshell puts its own share directory first in XDG_DATA_DIRS)
    readonly property string sounds: Quickshell.env("XDG_DATA_DIRS").split(":").find(d => d.endsWith("/apps"))
                                     + "/sounds/freedesktop/stereo/"

    QsTest { id: t }

    function send(name, hints) {
        const h = hints || [];
        sender.command = ["busctl", "--user", "--", "call", "org.freedesktop.Notifications",
                          "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify",
                          "susssasa{sv}i", "Mail", "0", "", name, "body", "0", String(h.length / 3)]
                         .concat(h).concat(["-1"]);
        sender.running = true;
    }
    Process {
        id: sender
        onExited: code => {
            t.compare(code, 0, "busctl delivered it");
            root.sent++;
        }
    }
    Process {
        id: reader
        command: ["sh", "-c", "cat \"$FAKE_PW_PLAY\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.played = text.split("\n").filter(l => l !== "")
        }
    }

    property real since: 0           // when the wait for the log began; -1 once it is being read

    function step() {
        const S = NotificationService;
        if (stage % 2 === 1) {                  // waiting for the log
            if (sender.running || reader.running) return;
            if (since >= 0) {
                if (since === 0) since = Date.now();
                if (Date.now() - since < 800) return;
                since = -1;
                reader.running = true;
                return;
            }
            since = 0;
            stage++;
            return;
        }
        switch (stage) {
        case 0:
            t.compare(Settings.value("notifications.sound"), true, "on by default");
            send("plain");
            break;
        case 2:
            t.compare(played.length, 1, "a popup plays a sound");
            t.compare(played[0], "--media-role=Notification " + sounds + "message-new-instant.oga",
                      "the theme's message sound, as a notification");
            send("named", ["sound-name", "s", "bell"]);
            break;
        case 4:
            t.compare(played[1], "--media-role=Notification " + sounds + "bell.oga", "the sender's sound-name");
            send("unknown", ["sound-name", "s", "no-such-sound"]);
            break;
        case 6:
            t.compare(played[2], "--media-role=Notification " + sounds + "message-new-instant.oga",
                      "an unknown name falls back to the message sound");
            send("file", ["sound-file", "s", sounds + "bell.oga"]);
            break;
        case 8:
            t.compare(played[3], "--media-role=Notification " + sounds + "bell.oga", "the sender's sound-file");
            send("hush", ["suppress-sound", "b", "true"]);
            break;
        case 10:
            t.compare(played.length, 4, "suppress-sound: silent");
            S.setDnd(true);
            send("quiet");
            break;
        case 12:
            t.compare(played.length, 4, "Do not disturb: silent");
            send("urgent", ["urgency", "y", "2"]);
            break;
        case 14:
            t.compare(played.length, 5, "a critical one plays through Do not disturb");
            S.setDnd(false);
            Settings.set("notifications.sound", false);
            send("off");
            break;
        case 16:
            t.compare(played.length, 5, "the setting off: silent");
            Settings.set("notifications.sound", true);
            send("burst1");
            break;
        case 18:
            if (sender.running) return;
            send("burst2");                     // while the first still plays
            break;
        case 20:
            t.compare(played.length, 6, "a burst plays once");
            t.compare(root.sent, 10, "every notification arrived");
            t.compare(S.list.length, 10, "and was kept");
            t.done();
            stage = 99;
            return;
        default:
            return;
        }
        stage = stage === 16 ? 18 : stage + 1;   // the burst's second goes before the log is read
    }

    Timer { interval: 100; repeat: true; running: true; onTriggered: root.step() }
    Timer {
        interval: 25000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage + ", played " + JSON.stringify(root.played));
            t.done();
        }
    }
}
