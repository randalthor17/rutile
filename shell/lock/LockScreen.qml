// The lock screen (plan 2.8): Quickshell's WlSessionLock (ext-session-lock) covers every screen with a LockPanel
// and PamContext checks the password. The shell creates it in a LazyLoader when locking (D31); on a correct
// password its motion runs back (the clock and field sink away, the wallpaper sharpens), then it unlocks and
// `unlocked` asks the shell to unload it. logind's LockedHint follows it, for idle managers. Nothing else unlocks it: there is no IPC call for
// that. If the shell dies while locked, the compositor keeps the screens locked and blank (by design of the
// protocol); starting the shell and locking again gives a lock screen back.
//
// PAM: the `login` service in /etc/pam.d, which every Linux system has. RUTILE_PAM_DIR and RUTILE_PAM_CONFIG
// override it, for tests only (a test's own directory with pam_permit or pam_deny).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.common
import qs.services
import "LoginSignals.js" as LoginSignals

Scope {
    id: root

    property bool locked: true
    readonly property alias secure: lock.secure
    readonly property alias pam: pam
    property bool busy: false
    property string error: ""
    property string message: ""
    property string pending: ""          // the password, only until PAM asks for it
    property int attempts: 0             // failed ones, for the state (tests)
    property bool leaving: false         // the password was right: the motion runs back, then it unlocks
    readonly property alias progress: motion.value
    // The motion starts once a screen's wallpaper is ready, or after half a second whatever happens.
    property bool started: false
    Timer {
        interval: 500
        running: !root.started
        onTriggered: root.started = true
    }

    // The lock's motion (LockPanel.progress), on the default spatial spring like every popup; Motion.speed applies.
    Spring {
        id: motion
        value: 0
        target: root.leaving || !root.started ? 0 : 1
        onSettledChanged: root.finishLeaving()
    }
    // with motion off the spring is already at rest, so leaving is checked here too
    onLeavingChanged: Qt.callLater(finishLeaving)
    function finishLeaving() {
        if (!leaving || !locked || !motion.settled || motion.value > 0.001) return;
        locked = false;
        unlocked();
    }

    // our session's, never "auto" (a test shell outside the session must not touch the real one)
    readonly property string sessionPath: LoginSignals.sessionPath(Quickshell.env("XDG_SESSION_ID"))
    function setLockedHint(on) {
        if (sessionPath === "") return;
        Quickshell.execDetached(["busctl", "--system", "call", "org.freedesktop.login1", sessionPath,
                                 "org.freedesktop.login1.Session", "SetLockedHint", "b", on ? "true" : "false"]);
    }
    onSecureChanged: if (secure) setLockedHint(true)
    onUnlocked: setLockedHint(false)

    signal unlocked()

    function submit(password) {
        if (busy || leaving) return;
        error = "";
        message = "";
        pending = password;
        busy = true;
        if (!pam.start()) {
            pending = "";
            busy = false;
            error = "Could not check the password";
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    PamContext {
        id: pam
        config: Quickshell.env("RUTILE_PAM_CONFIG") || "login"
        configDirectory: Quickshell.env("RUTILE_PAM_DIR") || "/etc/pam.d"
        onPamMessage: {
            if (responseRequired && !responseVisible && root.pending !== "") {
                const p = root.pending;
                root.pending = "";
                respond(p);
            } else if (responseRequired) {
                // a second question (a one-time code, a new password): not supported; stop rather than hang
                abort();
                root.busy = false;
                root.error = message || "Not supported here";
            } else {
                root.message = message;
            }
        }
        onCompleted: result => {
            root.pending = "";
            root.busy = false;
            if (result === PamResult.Success) {
                root.message = "";
                root.leaving = true;
            } else {
                root.attempts++;
                root.error = result === PamResult.Failed ? "Wrong password"
                           : result === PamResult.MaxTries ? "Too many tries; wait a moment"
                           : "Could not check the password";
            }
        }
    }

    WlSessionLock {
        id: lock
        locked: root.locked

        WlSessionLockSurface {
            color: Colors.surface
            LockPanel {
                anchors.fill: parent
                now: clock.date
                user: Quickshell.env("USER")
                busy: root.busy
                error: root.error
                message: root.message
                wallpaper: Settings.value("wallpaper.path") ?? ""
                progress: root.progress
                onBackgroundReadyChanged: if (backgroundReady) root.started = true
                Component.onCompleted: if (backgroundReady) root.started = true
                onSubmitted: password => root.submit(password)
                onEdited: root.error = ""
            }
        }
    }
}
