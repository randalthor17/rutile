import QtQuick
import QtTest
import qs.common
import qs.components

TestCase {
    id: root
    name: "PopupMotion"
    width: 400
    height: 400
    visible: true
    when: windowShown

    Component {
        id: popupComp
        Rectangle {
            id: popup
            width: 100
            height: 80
            property bool shown: true
            readonly property alias motion: motion
            PopupMotion { id: motion; target: popup; shown: popup.shown; origin: Item.TopRight }
        }
    }
    Component {
        id: loaderComp
        PopupLoader {
            origin: Item.TopLeft
            sourceComponent: Rectangle { objectName: "popup"; width: 50; height: 50 }
        }
    }
    Component { id: spyComp; SignalSpy {} }

    function cleanup() { Motion.speed = 1; }

    function test_grows_in_and_shrinks_away() {
        var p = createTemporaryObject(popupComp, root);
        var hidden = createTemporaryObject(spyComp, root, { target: p.motion, signalName: "hidden" });
        verify(p.scale < 0.9, "starts small");
        compare(p.scale, p.motion.fromScale);
        compare(p.transformOrigin, Item.TopRight);
        tryCompare(p, "scale", 1, 2000);
        tryCompare(p, "opacity", 1, 2000);
        verify(p.enabled);
        p.shown = false;
        verify(!p.enabled, "no input while it goes away");
        verify(p.motion.visible);
        tryCompare(hidden, "count", 1, 2000);
        compare(p.scale, p.motion.fromScale);
        compare(p.opacity, 0);
        verify(!p.motion.visible);
    }

    function test_speed_changes_how_long_it_takes() {
        function timeToOpen() {
            var p = createTemporaryObject(popupComp, root);
            var start = Date.now();
            tryVerify(function () { return p.motion.settled; }, 5000);
            return Date.now() - start;
        }
        var normal = timeToOpen();
        Motion.speed = 4;
        var fast = timeToOpen();
        verify(fast < normal / 2, "4x faster: " + fast + " ms vs " + normal + " ms");
        Motion.speed = 0;
        var p = createTemporaryObject(popupComp, root);
        tryCompare(p, "scale", 1, 200, "speed 0: open at once");
    }

    function test_loader_keeps_the_popup_until_it_has_closed() {
        var l = createTemporaryObject(loaderComp, root);
        compare(l.item, null, "closed: not loaded");
        l.open = true;
        verify(l.item, "loaded on open");
        verify(l.item.scale < 0.9, "and grows in");
        compare(l.item.transformOrigin, Item.TopLeft);
        tryCompare(l.item, "scale", 1, 2000);
        l.open = false;
        verify(l.item, "still there while it closes");
        verify(!l.item.enabled);
        tryCompare(l, "item", null, 2000, "unloaded once closed");
        l.open = true;
        verify(l.item, "opens again");
    }
}
