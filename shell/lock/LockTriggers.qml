// What locks the screen besides the power menu and IPC (plan 2.8), always running while the shell does:
// - logind's Lock signal for our session (`loginctl lock-session`, idle managers), heard with `dbus-monitor
//   --system` (part of D-Bus; it needs no privileges for signals). Its Unlock is ignored on purpose: any program
//   of the user's could send it.
// - Suspend (lock.beforeSleep): a logind delay inhibitor holds the suspend until the lock covers the screens
//   (`systemd-inhibit`), so the computer never wakes up showing the session; it is taken again on resume.
// - Idle (lock.idleMinutes): Quickshell's IdleMonitor (ext-idle-notify), which honours idle inhibitors.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import "LoginSignals.js" as LoginSignals

Scope {
    id: root

    required property bool locked
    required property bool secure        // the compositor has the lock on every screen

    signal lockRequested(string reason)  // logind, sleep or idle

    readonly property string sessionPath: LoginSignals.sessionPath(Quickshell.env("XDG_SESSION_ID"))
    readonly property int idleMinutes: Settings.value("lock.idleMinutes") ?? 0
    readonly property bool beforeSleep: Settings.value("lock.beforeSleep") === true
    property bool sleeping: false

    Process {
        id: monitor
        running: root.sessionPath !== ""
        command: ["dbus-monitor", "--system"].concat(LoginSignals.matchRules(root.sessionPath))
        property var state: ({ pending: "" })
        stdout: SplitParser {
            onRead: line => {
                const ev = LoginSignals.feed(line, monitor.state, root.sessionPath);
                if (ev === "lock") root.lockRequested("logind");
                else if (ev === "sleep") {
                    root.sleeping = true;
                    if (root.beforeSleep) root.lockRequested("sleep");
                } else if (ev === "wake") root.sleeping = false;
            }
        }
        onExited: code => console.warn("rutile: dbus-monitor for logind's signals exited (" + code + ")")
    }
    Component.onCompleted: {
        if (sessionPath === "")
            console.warn("rutile: no XDG_SESSION_ID: loginctl lock-session and lock before sleep do not reach the shell");
    }

    // Held while not about to sleep, or about to sleep and not yet locked; let go once the lock is secure.
    Process {
        id: inhibitor
        running: root.beforeSleep && root.sessionPath !== "" && !(root.sleeping && root.secure)
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Rutile Shell",
                  "--why=Lock the screen before sleep", "sleep", "infinity"]
    }

    IdleMonitor {
        enabled: root.idleMinutes > 0 && !root.locked
        timeout: root.idleMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.lockRequested("idle")
    }
}
