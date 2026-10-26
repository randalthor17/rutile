import QtQuick
import QtTest
import qs.common
import qs.shelf
import "../qs/shelf/ShelfApps.js" as ShelfApps

TestCase {
    id: root
    name: "Shelf"
    width: 900
    height: 200
    visible: true
    when: windowShown

    Component { id: shelfComp; Shelf { width: 900 } }
    Component { id: spyComp; SignalSpy {} }

    readonly property var pinned: [{ id: "org.gnome.Nautilus", name: "Files", icon: "" }, { id: "firefox", name: "Firefox", icon: "" }]
    readonly property var niriGroups: [
        { id: 1, idx: 1, name: "", active: true, windows: [{ id: 11, appId: "firefox", title: "a", focused: false },
                                                        { id: 10, appId: "kitty", title: "b", focused: true },
                                                        { id: 14, appId: "kitty", title: "c", focused: false }] },
        { id: 2, idx: 2, name: "web", active: false, windows: [{ id: 12, appId: "mystery", title: "d", focused: false }] }
    ]
    function lookup(appId) {
        return appId === "kitty" ? { name: "kitty", icon: "" } : appId === "firefox" ? { name: "Firefox", icon: "" } : null;
    }

    function test_pins() {
        compare(ShelfApps.pins("", id => ["thunar", "firefox", "chromium", "kitty"].indexOf(id) >= 0).join(),
                "thunar,firefox,kitty", "the first installed app of each group");
        compare(ShelfApps.pins("", id => false).length, 0);
        compare(ShelfApps.pins(" a, b ,,c", id => false).join(), "a,b,c", "an override wins, as given");
    }

    function test_decorate_and_ungrouped() {
        var g = ShelfApps.decorate(niriGroups, lookup);
        compare(g[0].windows.map(w => w.name).join(), "Firefox,kitty,kitty", "one per window, named by its app");
        compare(g[1].windows[0].name, "mystery", "no entry: its app id");
        compare(g[1].name, "web");
        compare(g[0].windows[1].id, 10);
        verify(g[0].windows[1].focused);
        var u = ShelfApps.ungrouped([{ appId: "a", title: "x", activated: false }, { appId: "b", title: "y", activated: true }]);
        compare(u.length, 1, "one group");
        compare(u[0].idx, 0, "without a number");
        compare(u[0].windows.map(w => w.id).join(), "0,1", "ids are the toplevel indices");
        verify(u[0].windows[1].focused);
        compare(ShelfApps.ungrouped([]).length, 0);
    }

    function test_shelf_shows_pins_and_workspaces() {
        var shelf = createTemporaryObject(shelfComp, root, { pinned: pinned, groups: ShelfApps.decorate(niriGroups, lookup) });
        waitForRendering(shelf);
        var launched = createTemporaryObject(spyComp, root, { target: shelf, signalName: "launched" });
        var focused = createTemporaryObject(spyComp, root, { target: shelf, signalName: "windowClicked" });
        compare(shelf.height, Spacing.xxxl);
        verify(findChild(shelf, "shelfDivider").visible);
        var ws1 = findChild(shelf, "shelfWorkspace_1");
        var ws2 = findChild(shelf, "shelfWorkspace_2");
        verify(ws1 && ws2);
        verify(ws1.x < ws2.x);
        compare(findChild(ws1, "shelfWorkspaceLabel").text, "1");
        compare(findChild(ws2, "shelfWorkspaceLabel").text, "web", "a named workspace shows its name");
        verify(Qt.colorEqual(ws1.color, Colors.secondaryContainer), "the active workspace is tinted");
        var w11 = findChild(ws1, "shelfWindow_11"), w10 = findChild(ws1, "shelfWindow_10"), w14 = findChild(ws1, "shelfWindow_14");
        verify(w11 && w10 && w14, "one icon per window, two kitty windows included");
        verify(w11.x < w10.x && w10.x < w14.x, "in layout order");
        verify(findChild(w10, "shelfRunningMark").visible, "the focused window is marked");
        tryCompare(findChild(w10, "shelfRunningMark"), "width", Spacing.lg, 2000);
        verify(!findChild(w14, "shelfRunningMark").visible, "the others are not");
        mouseClick(w14, w14.width / 2, w14.height / 2);
        compare(focused.count, 1);
        compare(focused.signalArguments[0][0].id, 14, "that exact window");
        var pin = findChild(shelf, "shelfPin_firefox");
        verify(pin.x < ws1.x, "pins first");
        verify(!findChild(pin, "shelfRunningMark").visible, "pins are launchers, without marks");
        mouseClick(pin, pin.width / 2, pin.height / 2);
        compare(launched.count, 1);
        compare(launched.signalArguments[0][0].id, "firefox");
        // without niri: one group without a number
        shelf.groups = ShelfApps.decorate(ShelfApps.ungrouped([{ appId: "kitty", title: "t", activated: true }]), lookup);
        waitForRendering(shelf);
        verify(!findChild(findChild(shelf, "shelfWorkspace_0"), "shelfWorkspaceLabel").visible);
        shelf.groups = [];
        verify(!findChild(shelf, "shelfDivider").visible, "no windows: no divider");
    }

    function test_wheel_moves_between_workspaces() {
        var shelf = createTemporaryObject(shelfComp, root, { pinned: pinned, groups: ShelfApps.decorate(niriGroups, lookup) });
        waitForRendering(shelf);
        var spy = createTemporaryObject(spyComp, root, { target: shelf, signalName: "workspaceScrolled" });
        mouseWheel(shelf, 450, shelf.height / 2, 0, -120);
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], 1, "down: the next workspace");
        mouseWheel(shelf, 450, shelf.height / 2, 0, 240);
        compare(spy.count, 3, "two notches, two workspaces");
        compare(spy.signalArguments[2][0], -1, "up: the previous");
        // a touchpad's small steps add up to a notch
        shelf.scrollBy(-50);
        shelf.scrollBy(-50);
        compare(spy.count, 3, "not a notch yet");
        shelf.scrollBy(-30);
        compare(spy.count, 4);
        compare(spy.signalArguments[3][0], 1);
        compare(shelf.wheelRest, -10, "the rest carries over");
        var wheel = findChild(shelf, "shelfWheel");
        compare(wheel.acceptedDevices & PointerDevice.TouchPad, PointerDevice.TouchPad, "niri reports wheels as touchpads");
    }

    function test_blank_workspace_capsule() {
        var groups = [{ id: 3, idx: 3, name: "", active: true, windows: [] }];
        var shelf = createTemporaryObject(shelfComp, root, { pinned: pinned, groups: groups });
        waitForRendering(shelf);
        var ws3 = findChild(shelf, "shelfWorkspace_3");
        verify(ws3 && ws3.visible, "the blank workspace has a capsule");
        compare(findChild(ws3, "shelfWorkspaceLabel").text, "3");
        verify(Qt.colorEqual(ws3.color, Colors.secondaryContainer), "tinted: it is the active one");
    }

    function test_launcher_and_press() {
        var shelf = createTemporaryObject(shelfComp, root, { pinned: pinned });
        waitForRendering(shelf);
        var launcher = createTemporaryObject(spyComp, root, { target: shelf, signalName: "launcherClicked" });
        var l = findChild(shelf, "shelfLauncher");
        mouseClick(l, l.width / 2, l.height / 2);
        compare(launcher.count, 1);
        var b = findChild(shelf, "shelfPin_firefox");
        var face = b.children[0];
        mousePress(b, b.width / 2, b.height / 2);
        tryVerify(function () { return face.scale < 0.95; }, 2000, "pressed: smaller");
        mouseRelease(b, b.width / 2, b.height / 2);
        tryCompare(face, "scale", 1, 2000, "released: back");
        var fallback = findChild(b, "shelfFallbackIcon");
        verify(fallback.visible, "no icon: the app's initial");
        compare(fallback.children[0].text, "F");
    }
}
