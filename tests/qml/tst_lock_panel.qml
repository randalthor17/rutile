import QtQuick
import QtTest
import qs.common
import qs.lock

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
}
