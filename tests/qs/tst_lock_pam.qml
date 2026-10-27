// LockScreen's password check (plan 2.8) through real PAM, with the test's own PAM configurations (pam/: pam_deny,
// then pam_permit), never the system's or a real password. Offscreen there is no compositor to lock; only the
// PAM side is checked here (the Wayland side: tools/qtws.py and the nested niri check).
// env RUTILE_PAM_DIR=@WS@/pam
// env RUTILE_PAM_CONFIG=rutile-deny
import QtQuick
import Quickshell
import qs.lock

ShellRoot {
    id: root

    property int stage: 0
    property int unlockedCount: 0
    property real progressAtUnlock: -1
    property bool triedWhileLeaving: false

    QsTest { id: t }

    LockScreen {
        id: lock
        onUnlocked: {
            root.unlockedCount++;
            root.progressAtUnlock = lock.progress;
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (lock.busy) return;
            switch (root.stage) {
            case 0:
                t.compare(lock.pam.config, "rutile-deny", "RUTILE_PAM_CONFIG sets the service");
                lock.submit("wrong");
                t.verify(lock.busy, "checking");
                t.compare(lock.pending, "wrong", "held only until PAM asks");
                root.stage = 1;
                break;
            case 1:
                if (lock.progress < 0.99) return;   // fully in, so leaving has a motion to run back
                t.compare(lock.error, "Wrong password", "pam_deny: wrong password");
                t.compare(lock.attempts, 1, "one failed attempt");
                t.verify(lock.locked, "still locked");
                t.compare(lock.pending, "", "the password is not kept");
                t.compare(root.unlockedCount, 0);
                lock.pam.config = "rutile-permit";
                lock.submit("right");
                root.stage = 2;
                break;
            case 2:
                if (lock.locked && lock.leaving && !root.triedWhileLeaving) {
                    root.triedWhileLeaving = true;
                    lock.submit("again");
                    t.verify(!lock.busy, "a password while it leaves is ignored");
                }
                if (lock.locked) return;         // the motion runs back first
                t.verify(root.triedWhileLeaving, "it was still locked while leaving");
                t.verify(root.progressAtUnlock >= 0 && root.progressAtUnlock < 0.01,
                         "unlocked only once the motion had run back: " + root.progressAtUnlock);
                t.verify(lock.leaving, "it left through its motion");
                t.compare(lock.error, "", "no error");
                t.verify(!lock.locked, "pam_permit: unlocked");
                t.compare(root.unlockedCount, 1, "unlocked once");
                t.compare(lock.pending, "", "nothing kept");
                t.done();
                root.stage = 3;
                break;
            }
        }
    }
    Timer {
        interval: 10000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage + " (error " + lock.error + ")");
            t.done();
        }
    }
}
