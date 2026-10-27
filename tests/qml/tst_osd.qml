import QtQuick
import QtTest
import qs.common
import qs.osd

TestCase {
    id: root
    name: "Osd"
    width: 400
    height: 200
    visible: true
    when: windowShown

    function init() { mouseMove(root, 1, 1); }
    function cleanup() { Motion.speed = 1; }

    // y: the pointer rests above it, off it
    Component { id: panelComp; OsdPanel { y: 100; holdTime: 600 } }
    Component { id: spyComp; SignalSpy {} }

    function test_show_and_hold() {
        const p = createTemporaryObject(panelComp, root, { value: 0.4 });
        const hidden = createTemporaryObject(spyComp, root, { target: p, signalName: "hidden" });
        verify(!p.open, "closed until shown");
        p.show("volume");
        verify(p.open);
        compare(p.kind, "volume");
        compare(p.iconName, "music_note");
        tryCompare(p.slider, "value", 0.4);
        tryVerify(() => p.scale > 0.95 && p.opacity > 0.95, 1000, "grows in");
        wait(400);
        p.show("brightness");             // a change while it shows keeps it open, on the new kind
        compare(p.kind, "brightness");
        compare(p.iconName, "brightness_medium");
        wait(400);
        verify(p.open, "the hold started again at the second change");
        tryCompare(p, "open", false, 1500, "gone after the hold");
        tryCompare(hidden, "count", 1, 3000, "then hidden, once it has closed");
    }

    function test_muted() {
        const p = createTemporaryObject(panelComp, root, { value: 0.6, muted: true });
        p.show("volume");
        compare(p.iconName, "music_off");
        tryCompare(p.slider, "value", 0, 1000, "muted shows 0");
        p.show("brightness");
        tryCompare(p.slider, "value", 0.6, 1000, "brightness ignores the mute");
        compare(p.iconName, "brightness_medium");
    }

    function test_held_while_hovered_or_dragged() {
        const p = createTemporaryObject(panelComp, root, { value: 0.5 });
        const moved = createTemporaryObject(spyComp, root, { target: p, signalName: "moved" });
        p.show("brightness");
        mouseMove(p, p.width / 2, p.height / 2);
        tryVerify(() => p.held, 1000, "the pointer is on it");
        wait(900);
        verify(p.open, "stays while the pointer is on it");
        mousePress(p.slider, p.slider.width * 0.25, p.slider.height / 2);
        mouseMove(p.slider, p.slider.width * 0.2, p.slider.height / 2);
        verify(moved.count > 0, "dragging reports the level");
        compare(moved.signalArguments[moved.count - 1][0], "brightness", "with its kind");
        verify(moved.signalArguments[moved.count - 1][1] < 0.3);
        mouseMove(root, 1, 1);
        wait(900);
        verify(p.open, "stays while the slider is held, also with the pointer off it");
        mouseRelease(root, 1, 1);
        tryVerify(() => !p.slider.pressed && !p.held, 500, "let go");
        wait(300);
        verify(p.open, "the hold starts again on letting go");
        tryCompare(p, "open", false, 1500);
    }

    function test_motion_off() {
        Motion.speed = 0;
        const p = createTemporaryObject(panelComp, root);
        const hidden = createTemporaryObject(spyComp, root, { target: p, signalName: "hidden" });
        p.show("volume");
        tryCompare(p, "open", false, 1000);
        tryCompare(hidden, "count", 1, 500, "closes at once with motion off");
    }
}
