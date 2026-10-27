// With motion off (Motion.speed 0) a right password still unlocks: the spring is already at rest when it leaves.
// env RUTILE_PAM_DIR=@WS@/pam
// env RUTILE_PAM_CONFIG=rutile-permit
import QtQuick
import Quickshell
import qs.common
import qs.lock

ShellRoot {
    id: root
    QsTest { id: t }
    Component.onCompleted: Motion.speed = 0
    LockScreen {
        id: lock
        onUnlocked: {
            t.verify(true, "unlocked with motion off");
            t.done();
        }
    }
    Timer {
        interval: 300
        running: true
        onTriggered: lock.submit("any")
    }
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            t.verify(false, "never unlocked (leaving " + lock.leaving + ", progress " + lock.progress + ")");
            t.done();
        }
    }
}
