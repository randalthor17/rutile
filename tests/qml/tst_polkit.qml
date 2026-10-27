import QtQuick
import QtTest
import qs.common
import qs.polkit

TestCase {
    id: root
    name: "PolkitDialog"
    width: 900
    height: 600
    visible: true
    when: windowShown

    function cleanup() { Motion.speed = 1; }

    // Quickshell's AuthFlow as far as the dialog uses it: polkit asks, the dialog answers.
    Component {
        id: flowComp
        QtObject {
            property string message: "Authentication is needed to run `/usr/bin/true' as the super user"
            property string actionId: "org.freedesktop.policykit.exec"
            property var identities: []
            property var selectedIdentity: identities.length ? identities[0] : null
            property bool isResponseRequired: true
            property string inputPrompt: "Password: "
            property bool responseVisible: false
            property string supplementaryMessage: ""
            property bool supplementaryIsError: false
            property bool isCompleted: false
            property bool isCancelled: false
            property var submitted: []
            property int cancels: 0
            signal authenticationFailed()
            function submit(value) {
                submitted = submitted.concat([value]);
                isResponseRequired = false;      // as AuthFlow does until the next try asks again
            }
            function cancelAuthenticationRequest() {
                cancels++;
                isCancelled = true;              // AuthFlow may complete it later, or not
            }
        }
    }
    Component { id: identityComp; QtObject { property string string: ""; property string displayName: "" } }
    Component { id: dialogComp; PolkitDialog { anchors.fill: parent } }
    Component { id: spyComp; SignalSpy {} }

    function make(props) {
        const f = createTemporaryObject(flowComp, root, props ?? {});
        const d = createTemporaryObject(dialogComp, root, { flow: f });
        return { f: f, d: d, hidden: createTemporaryObject(spyComp, root, { target: d, signalName: "hidden" }) };
    }
    function text(d, name) { return findChild(d, name).text; }
    function type(text) {
        for (const c of text) keyClick(c);
    }

    function test_shows_what_is_asked() {
        const me = createTemporaryObject(identityComp, root, { string: "rand", displayName: "Rand" });
        const t = make({ identities: [me] });
        verify(t.d.shown && t.d.asking);
        compare(text(t.d, "polkitMessage"), t.f.message);
        compare(text(t.d, "polkitIdentity"), "Rand");
        verify(findChild(t.d, "polkitIdentity").visible, "one identity: its name, no chips");
        verify(!findChild(t.d, "polkitIdentity_0"));
        compare(t.d.field.echoMode, TextInput.Password);
        verify(t.d.card.scale < 0.9, "grows in");
        tryVerify(() => t.d.card.scale > 0.99 && t.d.card.opacity > 0.99, 2000);
        tryVerify(() => t.d.field.activeFocus, 1000, "the password field has the keyboard");
    }

    function test_enter_submits_and_clears() {
        const t = make();
        tryVerify(() => t.d.field.activeFocus, 1000);
        const auth = findChild(t.d, "polkitAuthenticate");
        verify(!auth.enabled, "nothing to send yet");
        keyClick(Qt.Key_Return);
        compare(t.f.submitted.length, 0, "not empty");
        type("hunter2");
        verify(auth.enabled);
        keyClick(Qt.Key_Return);
        compare(t.f.submitted, ["hunter2"]);
        compare(t.d.field.text, "", "never kept");
        verify(!t.d.asking && t.d.shown, "checking, still open");
        verify(t.d.field.readOnly);
        type("more");
        compare(t.d.field.text, "", "no typing while polkit checks");
        t.d.submit();
        compare(t.f.submitted.length, 1);
    }

    function test_wrong_password_and_retry() {
        const t = make();
        tryVerify(() => t.d.field.activeFocus, 1000);
        type("nope");
        keyClick(Qt.Key_Return);
        t.f.authenticationFailed();
        t.f.isResponseRequired = true;           // polkit's next try asks again
        compare(text(t.d, "polkitError"), "Wrong password. Try again.");
        verify(t.d.wrong);
        tryVerify(() => t.d.shakeOffset !== 0, 1000, "the field shakes");
        tryVerify(() => t.d.field.activeFocus, 1000);
        type("x");
        verify(!t.d.wrong, "typing clears it");
        compare(text(t.d, "polkitError"), "");
        verify(t.d.shown, "a wrong password does not close it");
    }

    function test_polkit_messages() {
        const t = make();
        t.f.supplementaryMessage = "Your password expires in 3 days";
        compare(text(t.d, "polkitError"), "Your password expires in 3 days");
        compare(findChild(t.d, "polkitError").color, Colors.surfaceVariantOn);
        t.f.supplementaryIsError = true;
        t.f.supplementaryMessage = "Account locked";
        compare(text(t.d, "polkitError"), "Account locked");
        compare(findChild(t.d, "polkitError").color, Colors.error);
        t.f.inputPrompt = "PIN: ";
        t.f.responseVisible = true;
        verify(t.d.field.echoMode === TextInput.Normal, "shown as typed when polkit says so");
    }

    function test_escape_and_cancel_close() {
        const t = make();
        tryVerify(() => t.d.field.activeFocus, 1000);
        type("half");
        keyClick(Qt.Key_Escape);
        compare(t.f.cancels, 1);
        compare(t.d.field.text, "");
        verify(!t.d.shown);
        tryCompare(t.hidden, "count", 1, 3000);
        compare(t.f.submitted.length, 0);
        compare(text(t.d, "polkitMessage"), t.f.message, "the card keeps its text while it goes");

        const u = make();
        tryVerify(() => u.d.card.scale > 0.99, 2000);
        mouseClick(u.d, 5, 5);
        verify(u.d.shown, "a click outside does not dismiss");
        mouseClick(findChild(u.d, "polkitCancel"));
        compare(u.f.cancels, 1);
        tryCompare(u.hidden, "count", 1, 3000);
    }

    function test_success_closes() {
        const t = make();
        tryVerify(() => t.d.card.scale > 0.99, 2000);
        t.f.isCompleted = true;
        verify(!t.d.shown);
        tryCompare(t.hidden, "count", 1, 3000);
        compare(t.f.cancels, 0);
        t.d.cancel();
        compare(t.f.cancels, 0, "nothing to cancel once done");
    }

    function test_flow_gone_closes_and_keeps_text() {
        const t = make();
        const msg = t.f.message;
        t.d.flow = null;
        verify(!t.d.shown);
        compare(text(t.d, "polkitMessage"), msg);
        tryCompare(t.hidden, "count", 1, 3000);
    }

    function test_several_identities() {
        const a = createTemporaryObject(identityComp, root, { string: "rand", displayName: "Rand" });
        const b = createTemporaryObject(identityComp, root, { string: "admin", displayName: "" });
        const t = make({ identities: [a, b] });
        verify(!findChild(t.d, "polkitIdentity").visible, "chips instead of one name");
        const c0 = findChild(t.d, "polkitIdentity_0");
        const c1 = findChild(t.d, "polkitIdentity_1");
        compare(c0.text, "Rand");
        compare(c1.text, "admin", "the user name when there is no full name");
        verify(c0.selected && !c1.selected);
        tryVerify(() => t.d.card.scale > 0.99, 2000);
        mouseClick(c1);
        compare(t.f.selectedIdentity, b);
        verify(c1.selected && !c0.selected);
    }

    function test_a_new_request_while_closing() {
        const t = make();
        t.f.authenticationFailed();
        verify(t.d.wrong);
        t.f.isCompleted = true;
        verify(!t.d.shown);
        const next = createTemporaryObject(flowComp, root, { message: "Mount the disk" });
        t.d.flow = next;
        verify(t.d.shown, "the next request shows");
        compare(text(t.d, "polkitMessage"), "Mount the disk");
        verify(!t.d.wrong, "the last request's wrong password is not this one's");
        tryVerify(() => t.d.card.scale > 0.99, 2000);
        compare(t.hidden.count, 0, "it never went");
    }

    function test_no_motion() {
        Motion.speed = 0;
        const t = make();
        tryVerify(() => t.d.card.scale > 0.99, 100, "at once");
        t.f.isCompleted = true;
        tryCompare(t.hidden, "count", 1, 500);
    }
}
