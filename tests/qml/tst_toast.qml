import QtQuick
import QtTest
import qs.common
import qs.toast

TestCase {
    id: root
    name: "Toast"
    width: 700
    height: 200
    visible: true
    when: windowShown

    function init() { mouseMove(root, 1, 1); }
    function cleanup() { Motion.speed = 1; }

    // y: the pointer rests above it, off it
    Component { id: toastComp; Toast { y: 100; holdTime: 600 } }
    Component { id: spyComp; SignalSpy {} }

    function test_show_and_hold() {
        const t = createTemporaryObject(toastComp, root, { text: "Saved" });
        const hidden = createTemporaryObject(spyComp, root, { target: t, signalName: "hidden" });
        verify(!t.open);
        verify(!t.actionButton.visible, "no action: no button");
        t.show();
        tryVerify(() => t.scale > 0.95 && t.opacity > 0.95, 1000, "grows in");
        wait(400);
        t.show();                               // shown again: the hold starts again
        wait(400);
        verify(t.open, "held from the second show");
        tryCompare(t, "open", false, 1500, "gone after the hold");
        tryCompare(hidden, "count", 1, 3000, "then hidden");
    }

    function test_held_while_hovered() {
        const t = createTemporaryObject(toastComp, root, { text: "Saved" });
        t.show();
        mouseMove(t, t.width / 2, t.height / 2);
        tryVerify(() => t.held, 1000);
        wait(900);
        verify(t.open, "stays while the pointer is on it");
        mouseMove(root, 1, 1);
        tryVerify(() => !t.held, 500);
        wait(300);
        verify(t.open, "the hold starts again when the pointer leaves");
        tryCompare(t, "open", false, 1500);
    }

    function test_action() {
        const t = createTemporaryObject(toastComp, root, { text: "Unpinned Files", actionText: "Undo" });
        const clicked = createTemporaryObject(spyComp, root, { target: t, signalName: "actionClicked" });
        t.show();
        verify(t.actionButton.visible);
        compare(t.actionButton.text, "Undo");
        tryVerify(() => t.scale > 0.95, 1000);
        mouseClick(t.actionButton);
        compare(clicked.count, 1, "the action");
        verify(!t.open, "and it goes");
    }

    function test_size() {
        const t = createTemporaryObject(toastComp, root, { text: "Hi" });
        verify(t.implicitWidth < 200, "as wide as its text: " + t.implicitWidth);
        compare(t.implicitHeight, 48, "one line");
        t.text = "A very long message ".repeat(20);
        compare(t.implicitWidth, t.maxWidth, "at most maxWidth");
        t.actionText = "Undo";
        t.width = t.implicitWidth;
        tryVerify(() => t.actionButton.x + t.actionButton.width <= t.width, 1000, "the action stays inside");
    }

    function test_motion_off() {
        Motion.speed = 0;
        const t = createTemporaryObject(toastComp, root, { text: "Saved" });
        const hidden = createTemporaryObject(spyComp, root, { target: t, signalName: "hidden" });
        t.show();
        tryCompare(t, "open", false, 1000);
        tryCompare(hidden, "count", 1, 500);
    }
}
