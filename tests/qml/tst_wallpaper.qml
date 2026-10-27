import QtQuick
import QtTest
import qs.common
import qs.wallpaper

TestCase {
    id: root
    name: "Wallpaper"
    width: 320
    height: 180
    visible: true
    when: windowShown

    function cleanup() { Motion.speed = 1; }
    function file(name) { return Qt.resolvedUrl("../data/" + name).toString().replace("file://", ""); }

    Component { id: viewComp; WallpaperView { anchors.fill: parent } }

    function test_none_is_the_surface() {
        const v = createTemporaryObject(viewComp, root);
        compare(v.front.source.toString(), "");
        compare(v.color, Colors.surface);
    }

    function test_crossfade() {
        const v = createTemporaryObject(viewComp, root);
        v.path = file("red.png");
        tryVerify(() => !v.fading && v.front.status === Image.Ready, 3000, "the first one fades in");
        compare(v.front.source.toString(), "file://" + file("red.png"));
        compare(v.front.opacity, 1);
        compare(v.back.source.toString(), "", "nothing else decoded");
        compare(v.front.sourceSize, Qt.size(320, 180), "decoded at the view's size");
        const red = v.front;
        v.path = file("green.png");
        tryVerify(() => v.fading, 2000, "the new one fades in");
        compare(v.front, red, "over the old one, still showing");
        verify(v.back.z > v.front.z, "above it");
        tryVerify(() => !v.fading, 3000);
        compare(v.front.source.toString(), "file://" + file("green.png"), "then it is the front");
        compare(v.front.sourceSize, Qt.size(320, 180), "decoded at the view's size too");
        compare(red.source.toString(), "", "and the old one is dropped");
        verify(v.back.z > v.front.z, "the next one loads above it");
        compare(v.back.opacity, 0, "unseen until it fades in");
    }

    function test_a_missing_file_keeps_the_current_one() {
        const v = createTemporaryObject(viewComp, root);
        v.path = file("red.png");
        tryVerify(() => !v.fading && v.front.status === Image.Ready, 3000);
        v.path = "/nonexistent/wallpaper.png";
        tryCompare(v.back, "source", "", 3000);
        compare(v.front.source.toString(), "file://" + file("red.png"), "still showing");
        verify(!v.fading);
    }

    function test_back_to_the_current_one_mid_load() {
        Motion.speed = 0.2;                      // a slow fade to interrupt
        const v = createTemporaryObject(viewComp, root);
        v.path = file("red.png");
        tryVerify(() => !v.fading && v.front.status === Image.Ready, 6000);
        v.path = file("green.png");
        tryVerify(() => v.fading, 2000);
        v.path = file("red.png");
        verify(!v.fading, "the fade stops");
        compare(v.back.source.toString(), "", "the new one is dropped");
        compare(v.front.source.toString(), "file://" + file("red.png"));
    }

    function test_cleared() {
        const v = createTemporaryObject(viewComp, root);
        v.path = file("red.png");
        tryVerify(() => !v.fading && v.front.status === Image.Ready, 3000);
        v.path = "";
        compare(v.front.source.toString(), "", "no wallpaper: the surface color");
        compare(v.back.source.toString(), "");
    }

    function test_motion_off() {
        Motion.speed = 0;
        const v = createTemporaryObject(viewComp, root);
        v.path = file("red.png");
        tryVerify(() => v.front.status === Image.Ready && v.front.source.toString() !== "", 3000, "shown at once");
    }
}
