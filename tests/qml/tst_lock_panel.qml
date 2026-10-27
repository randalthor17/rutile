import QtQuick
import QtTest
import qs.common
import qs.lock
import "../qs/lock/LoginSignals.js" as LoginSignals

TestCase {
    id: root
    name: "LockPanel"
    width: 800
    height: 600
    visible: true
    when: windowShown

    Component {
        id: panelComp
        LockPanel { anchors.fill: parent; now: new Date(2026, 9, 9, 8, 5); user: "rand"; use24h: false }
    }
    Component { id: spyComp; SignalSpy {} }

    function type(text) {
        for (const c of text) keyClick(c);
    }

    function test_shows_time_and_user() {
        const p = createTemporaryObject(panelComp, root);
        compare(p.timeText, "8:05");
        verify(p.dateText.length > 0);
        verify(p.field.activeFocus, "the field has the keyboard");
        compare(p.field.echoMode, TextInput.Password, "the password is never shown");
    }

    function test_submit() {
        const p = createTemporaryObject(panelComp, root);
        const sent = createTemporaryObject(spyComp, root, { target: p, signalName: "submitted" });
        keyClick(Qt.Key_Return);
        compare(sent.count, 0, "an empty field sends nothing");
        type("hunter2");
        compare(p.field.text, "hunter2");
        keyClick(Qt.Key_Return);
        compare(sent.count, 1);
        compare(sent.signalArguments[0][0], "hunter2", "the password");
        compare(p.field.text, "", "and the field is empty again");
        type("abc");
        keyClick(Qt.Key_Escape);
        compare(p.field.text, "", "Escape clears it");
    }

    function test_busy_takes_no_typing_and_sends_nothing() {
        const p = createTemporaryObject(panelComp, root, { busy: true });
        const sent = createTemporaryObject(spyComp, root, { target: p, signalName: "submitted" });
        type("abc");
        compare(p.field.text, "", "read-only while checking");
        p.field.text = "x";
        p.submit();
        compare(sent.count, 0);
    }

    function test_error_and_edit() {
        const p = createTemporaryObject(panelComp, root);
        const edited = createTemporaryObject(spyComp, root, { target: p, signalName: "edited" });
        p.error = "Wrong password";
        tryVerify(() => Math.abs(p.shakeOffset) > 1, 1000, "the field shakes");
        tryCompare(p, "shakeOffset", 0, 2000, "and comes back");
        type("a");
        compare(edited.count, 1, "typing after an error asks to clear it");
        compare(p.error, "Wrong password", "the owner clears it, not the panel (its binding stays)");
        p.error = "";                          // as LockScreen does
        type("b");
        compare(edited.count, 1, "no error: nothing to clear");
    }

    function test_motion() {
        const p = createTemporaryObject(panelComp, root, { progress: 0 });
        const content = findChild(p, "lockContent");
        compare(content.opacity, 0, "nothing on it at the start");
        verify(content.anchors.verticalCenterOffset > 0, "below its place");
        p.progress = 0.5;
        compare(content.opacity, 0.5);
        p.progress = 1.05;                       // the spring overshoots
        compare(p.shown, 1, "clamped");
        compare(content.anchors.verticalCenterOffset < 0, true, "the overshoot moves it, not the opacity");
        p.progress = 1;
        compare(content.anchors.verticalCenterOffset, 0, "in place");
        compare(findChild(p, "lockBlur").visible, false, "no wallpaper: no blur");
        compare(findChild(p, "lockSharp").source.toString(), "", "and no sharp copy");
        const sharp = findChild(p, "lockSharp");
        p.progress = 0;
        compare(sharp.opacity, 1, "sharp when the lock is out of the way");
        p.progress = 0.2;
        verify(sharp.opacity > 0 && sharp.opacity < 1, "fading as it blurs");
        p.progress = 0.3;
        compare(sharp.opacity, 0, "gone under a quarter of the way in");
    }

    function test_session_path() {
        compare(LoginSignals.sessionPath("3"), "/org/freedesktop/login1/session/_33", "a leading digit is escaped");
        compare(LoginSignals.sessionPath("c2"), "/org/freedesktop/login1/session/c2");
        compare(LoginSignals.sessionPath("12"), "/org/freedesktop/login1/session/_312");
        compare(LoginSignals.sessionPath("a-b"), "/org/freedesktop/login1/session/a_2db");
        compare(LoginSignals.sessionPath(""), "", "none");
        compare(LoginSignals.sessionPath(undefined), "");
        const rules = LoginSignals.matchRules("/org/freedesktop/login1/session/_33");
        verify(rules[0].indexOf("member='Lock',path='/org/freedesktop/login1/session/_33'") > 0);
        verify(rules[1].indexOf("member='PrepareForSleep'") > 0);
    }

    function test_feed() {
        const path = "/org/freedesktop/login1/session/_33";
        const s = { pending: "" };
        const sig = (p, iface, member) => "signal time=1793092071.704939 sender=:1.4 -> destination=(null destination) "
            + "serial=562 path=" + p + "; interface=" + iface + "; member=" + member;
        compare(LoginSignals.feed("dbus-monitor: unable to enable new-style monitoring: ...", s, path), "");
        compare(LoginSignals.feed(sig(path, "org.freedesktop.login1.Session", "Lock"), s, path), "lock", "our Lock");
        compare(LoginSignals.feed(sig(path, "org.freedesktop.login1.Session", "Unlock"), s, path), "", "Unlock is ignored");
        compare(LoginSignals.feed(sig("/org/freedesktop/login1/session/_34", "org.freedesktop.login1.Session", "Lock"),
                                  s, path), "", "another session's Lock");
        compare(LoginSignals.feed(sig("/org/freedesktop/login1/session/_333", "org.freedesktop.login1.Session", "Lock"),
                                  s, path), "", "a session whose path starts like ours");
        const sleep = sig("/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PrepareForSleep");
        compare(LoginSignals.feed(sleep, s, path), "", "its argument comes next");
        compare(LoginSignals.feed("   boolean true", s, path), "sleep");
        compare(LoginSignals.feed("   boolean true", s, path), "", "only right after the signal");
        LoginSignals.feed(sleep, s, path);
        compare(LoginSignals.feed("   boolean false", s, path), "wake");
        LoginSignals.feed(sleep, s, path);
        compare(LoginSignals.feed(sig(path, "org.freedesktop.login1.Session", "Lock"), s, path), "lock",
                "a new signal resets the pending argument");
        compare(LoginSignals.feed("   boolean true", s, path), "");
    }
}
