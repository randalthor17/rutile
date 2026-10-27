import QtQuick
import QtTest
import qs.common
import qs.power

TestCase {
    id: root
    name: "PowerOverlay"
    width: 900
    height: 500
    visible: true
    when: windowShown

    function cleanup() { Motion.speed = 1; }

    Component { id: overlayComp; PowerOverlay { anchors.fill: parent } }
    Component { id: spyComp; SignalSpy {} }

    function make() {
        const o = createTemporaryObject(overlayComp, root);
        o.forceActiveFocus();
        return { o: o, chosen: createTemporaryObject(spyComp, root, { target: o, signalName: "chosen" }),
                 dismissed: createTemporaryObject(spyComp, root, { target: o, signalName: "dismissed" }) };
    }

    function test_entries() {
        const t = make();
        compare(t.o.actions.map(a => a.id).join(), "lock,suspend,logout,reboot,poweroff");
        ["lock", "suspend", "logout", "reboot", "poweroff"].forEach(id => verify(findChild(t.o, "power_" + id), id));
        verify(t.o.content.scale < 0.9, "grows in");
        tryVerify(() => t.o.content.scale > 0.99 && t.o.content.opacity > 0.99, 2000);
    }

    function test_click_chooses() {
        const t = make();
        tryVerify(() => t.o.content.scale > 0.99, 2000);
        mouseClick(findChild(t.o, "powerButton_reboot"));
        compare(t.chosen.count, 1);
        compare(t.chosen.signalArguments[0][0], "reboot");
        compare(t.dismissed.count, 0);
        verify(!t.o.shown, "and it closes");
        mouseClick(findChild(t.o, "powerButton_lock"));
        compare(t.chosen.count, 1, "nothing more while it goes");
    }

    function test_click_elsewhere_dismisses() {
        const t = make();
        tryVerify(() => t.o.content.scale > 0.99, 2000);
        mouseClick(t.o, 10, 10);
        compare(t.dismissed.count, 1);
        compare(t.chosen.count, 0);
        verify(!t.o.shown, "it closes");
    }

    function test_keyboard() {
        const t = make();
        verify(!findChild(t.o, "power_lock").isCurrent, "no ring before the keyboard is used");
        keyClick(Qt.Key_Right);
        compare(t.o.current, 1);
        verify(findChild(t.o, "power_suspend").isCurrent, "the ring on the chosen one");
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Left);
        compare(t.o.current, 4, "wraps around");
        keyClick(Qt.Key_Tab);
        compare(t.o.current, 0);
        keyClick(Qt.Key_Return);
        compare(t.chosen.signalArguments[0][0], "lock");
        verify(!t.o.shown);
        const u = make();
        keyClick(Qt.Key_Escape);
        compare(u.dismissed.count, 1, "Escape dismisses");
        verify(!u.o.shown, "and it closes");
    }

    function test_closing_takes_no_choice() {
        const t = make();
        const hidden = createTemporaryObject(spyComp, root, { target: t.o, signalName: "hidden" });
        t.o.shown = false;
        t.o.choose(0);
        keyClick(Qt.Key_Escape);
        compare(t.chosen.count, 0, "nothing chosen while it goes");
        compare(t.dismissed.count, 0);
        tryCompare(hidden, "count", 1, 2000);
    }

    function test_motion_off_choice_comes_before_hidden() {
        Motion.speed = 0;
        const t = make();
        const order = [];
        t.o.chosen.connect(id => order.push("chosen " + id));
        t.o.hidden.connect(() => order.push("hidden"));
        t.o.choose(3);
        tryVerify(() => order.length === 2, 1000);
        compare(order.join(), "chosen reboot,hidden", "the window knows the choice when the menu has gone");
    }
}
