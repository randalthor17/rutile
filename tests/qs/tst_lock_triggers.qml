// LockTriggers (plan 2.8) with the fake dbus-monitor and systemd-inhibit (bin/): our session's Lock and a suspend
// ask to lock; another session's Lock and an Unlock do not; the delay inhibitor is held until the lock is secure.
// env PATH=@WS@/bin:@PATH@
// env XDG_SESSION_ID=7
// env FAKE_LOGIND=@WS@/logind.txt
// env FAKE_INHIBIT=@WS@/inhibit.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.lock

ShellRoot {
    id: root

    property var requests: []
    property bool locked: false
    property bool secure: false
    property int stage: 0
    readonly property string session: "/org/freedesktop/login1/session/_37"

    QsTest { id: t }

    LockTriggers {
        id: triggers
        locked: root.locked
        secure: root.secure
        onLockRequested: reason => root.requests = root.requests.concat([reason])
    }

    function signalLine(path, iface, member) {
        return "signal time=1.0 sender=:1.4 -> destination=(null destination) serial=1 path=" + path
            + "; interface=org.freedesktop.login1." + iface + "; member=" + member;
    }
    Process {
        id: append
        function lines(ls) {
            command = ["sh", "-c", 'printf "%s\\n" "$@" >> "$FAKE_LOGIND"', "sh"].concat(ls);
            running = true;
        }
    }
    Process {
        id: reader
        property string text: ""
        command: ["sh", "-c", 'cat "$FAKE_INHIBIT" 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: reader.text = text }
    }

    Timer {
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            if (append.running || reader.running) return;
            switch (root.stage) {
            case 0:
                t.compare(triggers.sessionPath, root.session, "our session's path");
                append.lines([root.signalLine("/org/freedesktop/login1/session/_38", "Session", "Lock"),
                              root.signalLine(root.session, "Session", "Unlock")]);
                break;
            case 1:
                t.compare(root.requests.join(), "", "another session's Lock, and Unlock: nothing");
                reader.running = true;
                break;
            case 2:
                t.verify(reader.text.indexOf("start --what=sleep --mode=delay") === 0, "the inhibitor is held: " + reader.text);
                append.lines([root.signalLine("/org/freedesktop/login1", "Manager", "PrepareForSleep"), "   boolean true"]);
                break;
            case 3:
                t.compare(root.requests.join(), "sleep", "a suspend asks to lock");
                reader.running = true;
                break;
            case 4:
                t.verify(reader.text.indexOf("stop") < 0, "held until the lock is secure");
                root.locked = true;
                root.secure = true;
                break;
            case 5:
                reader.running = true;
                break;
            case 6:
                t.verify(/stop\n$/.test(reader.text), "let go once secure: " + reader.text);
                append.lines([root.signalLine("/org/freedesktop/login1", "Manager", "PrepareForSleep"), "   boolean false",
                              root.signalLine(root.session, "Session", "Lock")]);
                break;
            case 7:
                t.compare(root.requests.join(), "sleep,logind", "our session's Lock asks to lock");
                reader.running = true;
                break;
            case 8:
                t.compare(reader.text.split("start").length - 1, 2, "taken again after resume");
                t.done();
                break;
            default:
                return;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage + ", requests " + root.requests.join());
            t.done();
        }
    }
}
