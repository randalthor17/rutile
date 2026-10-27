// The lock screen (plan 2.8): Quickshell's WlSessionLock (ext-session-lock) covers every screen with a LockPanel
// and PamContext checks the password. The shell creates it in a LazyLoader when locking (D31); on a correct
// password it unlocks and `unlocked` asks the shell to unload it. Nothing else unlocks it: there is no IPC call for
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

    signal unlocked()

    function submit(password) {
        if (busy) return;
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
                root.locked = false;
                root.unlocked();
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
                onSubmitted: password => root.submit(password)
                onEdited: root.error = ""
            }
        }
    }
}
