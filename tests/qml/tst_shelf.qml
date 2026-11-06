import QtQuick
import QtTest
import qs.common
import qs.shelf
import qs.components
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
        compare(ShelfApps.pins(undefined, id => ["thunar", "firefox", "chromium", "kitty"].indexOf(id) >= 0).join(),
                "thunar,firefox,kitty", "the first installed app of each group");
        compare(ShelfApps.pins(undefined, id => false).length, 0);
        compare(ShelfApps.pins(["a", "b", "", "c"], id => false).join(), "a,b,c", "the setting wins, as given");
        compare(ShelfApps.pins([], id => true).length, 0, "an empty setting pins nothing");
        compare(ShelfApps.pins(["firefox.desktop", "org.gnome.Nautilus.desktop", "foot"], id => true).join(),
                "firefox,org.gnome.Nautilus,foot", "ids written with .desktop name the same apps");
    }

    function test_move() {
        compare(ShelfApps.move(["a", "b", "c"], 1, -1).join(), "b,a,c");
        compare(ShelfApps.move(["a", "b", "c"], 1, 1).join(), "a,c,b");
        compare(ShelfApps.move(["a", "b", "c"], 0, -1).join(), "a,b,c", "not past the start");
        compare(ShelfApps.move(["a", "b", "c"], 2, 1).join(), "a,b,c", "nor the end");
        const ids = ["a", "b"];
        ShelfApps.move(ids, 0, 1);
        compare(ids.join(), "a,b", "the given list is not changed");
    }

    function test_menu_items() {
        const ids = info => ShelfApps.menuItems(info).map(i => i.separator ? "-" : i.id).join(",");
        compare(ids({ window: false, entry: true, actions: ["New private window"], pinned: true, editable: true }),
                "open,action:0,-,unpin", "a pin: open, its actions, unpin");
        compare(ids({ window: true, entry: true, actions: [], pinned: false, editable: true }), "open,-,pin,-,close",
                "a window: a new one, pin, close");
        compare(ShelfApps.menuItems({ window: true, entry: true, actions: [], pinned: false, editable: true })[0].text, "New window");
        compare(ids({ window: true, entry: false, actions: ["x"], pinned: false, editable: true }), "close",
                "a window without a desktop entry: only close");
        compare(ids({ window: false, entry: true, actions: [], pinned: true, editable: false }), "open", "pins set in Nix: no pin or unpin");
        compare(ShelfApps.menuItems({ window: false, entry: true, actions: ["A", "B"], pinned: true, editable: true })[2].text, "B");
    }

    function test_right_click_asks_for_the_menu() {
        var shelf = createTemporaryObject(shelfComp, root, { pinned: pinned, groups: ShelfApps.decorate(niriGroups, lookup) });
        waitForRendering(shelf);
        var asked = createTemporaryObject(spyComp, root, { target: shelf, signalName: "menuRequested" });
        var launched = createTemporaryObject(spyComp, root, { target: shelf, signalName: "launched" });
        var b = findChild(shelf, "shelfPin_firefox");
        mouseClick(b, b.width / 2, b.height / 2, Qt.RightButton);
        compare(asked.count, 1);
        compare(asked.signalArguments[0][0].app.id, "firefox");
        compare(asked.signalArguments[0][1], b.mapToItem(shelf, b.width / 2, 0).x, "its middle on the shelf");
        compare(launched.count, 0, "a right click does not launch");
        mouseClick(b, b.width / 2, b.height / 2);
        compare(launched.count, 1, "a left click still does");
        compare(asked.count, 1);
        var w = findChild(shelf, "shelfWindow_14");
        mouseClick(w, w.width / 2, w.height / 2, Qt.RightButton);
        compare(asked.count, 2);
        compare(asked.signalArguments[1][0].window.id, 14);
    }

    // D90: a press between the buttons closes the shell's popups; one on a button does what the button does
    function test_press_between_buttons() {
        var shelf = createTemporaryObject(shelfComp, root, { pinned: pinned, groups: ShelfApps.decorate(niriGroups, lookup) });
        waitForRendering(shelf);
        var pressed = createTemporaryObject(spyComp, root, { target: shelf, signalName: "pressed" });
        var launcher = createTemporaryObject(spyComp, root, { target: shelf, signalName: "launcherClicked" });
        mouseClick(shelf, 4, shelf.height / 2);
        compare(pressed.count, 1);
        var l = findChild(shelf, "shelfLauncher");
        mouseClick(l, l.width / 2, l.height / 2);
        compare(launcher.count, 1);
        compare(pressed.count, 1, "the launcher button toggles the launcher, not closes it");
        var b = findChild(shelf, "shelfPin_firefox");
        mouseClick(b, b.width / 2, b.height / 2);
        compare(pressed.count, 1);
    }

    // D115: the launcher at the left, the pins and windows in the middle, concave corners above the ends, and the bar
    // as see-through as the panels
    function test_layout_corners_translucency() {
        var shelf = createTemporaryObject(shelfComp, root, { y: 100, pinned: pinned, groups: ShelfApps.decorate(niriGroups, lookup) });
        waitForRendering(shelf);
        var l = findChild(shelf, "shelfLauncher");
        compare(l.x, Spacing.md, "the launcher at the left");
        compare(shelf.launcherX, l.x, "where the launcher window opens (D124)");
        var first = findChild(shelf, "shelfPin_org.gnome.Nautilus");
        var last = findChild(shelf, "shelfWorkspace_2");
        var left = first.mapToItem(shelf, 0, 0).x, right = last.mapToItem(shelf, last.width, 0).x;
        verify(Math.abs((left + right) / 2 - shelf.width / 2) <= 1, "the pins and windows centered: " + left + ".." + right);
        verify(left > l.x + l.width, "clear of the launcher");
        var r = shelf.cornerRadius;
        verify(r > 0);
        var cl = findChild(shelf, "shelfCorner_left"), cr = findChild(shelf, "shelfCorner_right");
        compare([cl.x, cl.y, cl.width, cl.height], [0, -r, r, r], "above the left end");
        compare([cr.x, cr.y], [shelf.width - r, -r], "and the right one");
        tryVerify(function () {
            var img = grabImage(root);
            var bar = img.pixel(shelf.width / 2, 100 - r + 1), edge = img.pixel(1, 100 - 2), inner = img.pixel(r - 1, 100 - r + 1);
            // inside the quarter circle (centered on the corner's top inner point), under a straight diagonal
            var curve = img.pixel(Math.round(0.4 * r), Math.round(100 - 0.4 * r));
            return Qt.colorEqual(edge, shelf.color) && !Qt.colorEqual(inner, shelf.color) && !Qt.colorEqual(bar, shelf.color)
                && !Qt.colorEqual(curve, shelf.color);
        }, 3000, "filled at the screen's side, curved open toward the middle, nothing over the rest");
        compare(shelf.color.a, 1, "solid by default");
        Panels.opacity = 0.7;
        verify(Math.abs(shelf.color.a - 0.7) < 0.01, "as see-through as the panels");
        compare(cl.data[0].fillColor, shelf.color, "the corners too");
        Panels.opacity = 1;
    }

    function test_toggle_pin() {
        compare(ShelfApps.togglePin(["a", "b"], "c").join(), "a,b,c", "pins at the end");
        compare(ShelfApps.togglePin(["a", "b", "c"], "b").join(), "a,c", "unpins in place");
        compare(ShelfApps.togglePin([], "a").join(), "a");
        compare(ShelfApps.togglePin(["a", "b"], "a").join(), "b", "the first one too");
        const ids = ["a"];
        ShelfApps.togglePin(ids, "b");
        compare(ids.join(), "a", "the given list is not changed");
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
        verify(!findChild(pin, "shelfRunningMark").visible, "no window open: no mark");
        shelf.pinned = [pinned[0], Object.assign({}, pinned[1], { running: true })];
        waitForRendering(shelf);
        pin = findChild(shelf, "shelfPin_firefox");
        verify(findChild(pin, "shelfRunningMark").visible, "a window open: a dot");
        compare(findChild(pin, "shelfRunningMark").width, Spacing.xs, "a dot, not the focused window's dash");
        verify(!findChild(findChild(shelf, "shelfPin_org.gnome.Nautilus"), "shelfRunningMark").visible);
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

    function test_running_and_drag_helpers() {
        compare(ShelfApps.runningIds(niriGroups, a => a === "mystery" ? "" : a + ".desktop").join(),
                "firefox.desktop,kitty.desktop", "each app once; a window without an entry left out");
        compare(ShelfApps.runningIds([], a => a).length, 0);
        compare(ShelfApps.dropIndex(0, 70, 56, 3), 1, "past half a slot: the next place");
        compare(ShelfApps.dropIndex(0, 20, 56, 3), 0);
        compare(ShelfApps.dropIndex(2, -500, 56, 3), 0, "no further than the first");
        compare(ShelfApps.dropIndex(0, 500, 56, 3), 2, "nor the last");
        compare(ShelfApps.dropIndex(1, 100, 0, 3), 1);
        compare([0, 1, 2, 3].map(i => ShelfApps.dragShift(i, 0, 2)).join(), "0,-1,-1,0", "dragged right: those passed step left");
        compare([0, 1, 2, 3].map(i => ShelfApps.dragShift(i, 3, 1)).join(), "0,1,1,0", "dragged left: those passed step right");
        compare([0, 1].map(i => ShelfApps.dragShift(i, -1, -1)).join(), "0,0", "no drag");
    }

    function test_drag_reorders_pins() {
        const three = pinned.concat([{ id: "kitty", name: "kitty", icon: "" }]);
        var shelf = createTemporaryObject(shelfComp, root, { pinned: three });
        waitForRendering(shelf);
        var moved = createTemporaryObject(spyComp, root, { target: shelf, signalName: "pinsReordered" });
        var launched = createTemporaryObject(spyComp, root, { target: shelf, signalName: "launched" });
        var files = findChild(shelf, "shelfPin_org.gnome.Nautilus");
        const slot = files.width + Spacing.sm;
        const y = files.height / 2;
        mousePress(files, files.width / 2, y);
        for (let i = 1; i <= 10; i++) mouseMove(files, files.width / 2 + i * slot * 0.2, y);
        compare(shelf.dragTo, 2, "two slots right: the last place");
        tryCompare(findChild(shelf, "shelfPin_kitty"), "shift", -slot, 2000, "the one passed steps aside");
        compare(findChild(shelf, "shelfPin_firefox").shift, -slot);
        mouseRelease(files, files.width / 2 + 2 * slot, y);
        compare(moved.count, 1);
        compare(moved.signalArguments[0][0].join(), "firefox,kitty,org.gnome.Nautilus");
        compare(launched.count, 0, "a drag launches nothing");
        compare(shelf.dragFrom, -1);
        // a short wobble is still a click
        var fox = findChild(shelf, "shelfPin_firefox");
        mousePress(fox, fox.width / 2, y);
        mouseMove(fox, fox.width / 2 + 2, y);
        mouseRelease(fox, fox.width / 2 + 2, y);
        compare(moved.count, 1, "not moved");
        compare(launched.count, 1, "launched");
        // dragged away and back: nothing saved
        files = findChild(shelf, "shelfPin_org.gnome.Nautilus");
        mousePress(files, files.width / 2, y);
        for (let i = 1; i <= 10; i++) mouseMove(files, files.width / 2 + i * slot * 0.2, y);
        for (let i = 9; i >= 0; i--) mouseMove(files, files.width / 2 + i * slot * 0.2, y);
        mouseRelease(files, files.width / 2, y);
        compare(moved.count, 1, "back where it was: not moved");
        // set in Nix: they stay put
        shelf.pinsMovable = false;
        mousePress(files, files.width / 2, y);
        for (let i = 1; i <= 10; i++) mouseMove(files, files.width / 2 + i * slot * 0.2, y);
        mouseRelease(files, files.width / 2 + 2 * slot, y);
        compare(moved.count, 1, "no drag while Nix sets the pins");
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

    // ---- tooltips (D106) ----
    function test_tooltips() {
        var shelf = createTemporaryObject(shelfComp, root, { pinned: pinned, groups: ShelfApps.decorate(niriGroups, lookup),
                                                             tooltipDelay: 200 });
        waitForItemPolished(shelf);
        const files = findChild(shelf, "shelfPin_org.gnome.Nautilus"), fox = findChild(shelf, "shelfPin_firefox");
        mouseMove(files);
        compare(shelf.tooltipText, "", "not at once");
        tryCompare(shelf, "tooltipText", "Files", 1000, "after the wait");
        compare(shelf.tooltipX, files.mapToItem(shelf, files.width / 2, 0).x, "over the button's middle");
        mouseMove(fox);
        compare(shelf.tooltipText, "Firefox", "from one button to the next at once");
        compare(shelf.tooltipX, fox.mapToItem(shelf, fox.width / 2, 0).x);
        mouseMove(shelf, 5, 5);
        tryCompare(shelf, "tooltipText", "", 500, "gone off the buttons");
        mouseMove(fox, 5, 5);
        wait(50);
        mouseMove(shelf, 5, 5);
        wait(400);
        compare(shelf.tooltipText, "", "a pass over a button shows nothing");
        // a window says its title
        const kitty = findChild(shelf, "shelfWindow_10");
        mouseMove(kitty);
        tryCompare(shelf, "tooltipText", "b", 1000);
        mouseClick(kitty);
        compare(shelf.tooltipText, "", "a press hides it");
        mouseMove(fox);
        wait(100);
        mouseClick(fox, fox.width / 2, fox.height / 2, Qt.RightButton);
        wait(300);
        compare(shelf.tooltipText, "", "nor does it come under its menu");
    }
    // stand-ins for buttons, to send the leave before the enter, as a compositor may
    Component { id: fakeButton; Item { property bool hovered: false; property string tooltip: ""; width: 10; height: 10 } }
    function test_tooltip_leave_before_enter() {
        var shelf = createTemporaryObject(shelfComp, root, { pinned: pinned, tooltipDelay: 200 });
        const a = createTemporaryObject(fakeButton, shelf, { tooltip: "A" }), b = createTemporaryObject(fakeButton, shelf, { tooltip: "B", x: 20 });
        a.hovered = true;
        shelf.hover(a);
        tryCompare(shelf, "tooltipText", "A", 1000);
        a.hovered = false;
        shelf.hover(a);
        b.hovered = true;
        shelf.hover(b);
        compare(shelf.tooltipText, "B", "the next button's at once, though the last one was left first");
        wait(0);
        compare(shelf.tooltipText, "B");
    }
    Component { id: tipComp; Tooltip {} }
    function test_tooltip_component() {
        const tip = createTemporaryObject(tipComp, root, { text: "Hi" });
        tryCompare(tip, "opacity", 1);
        compare(tip.width, ControlSpec.tooltipSpec.impl.minWidth, "a short text: the smallest width");
        compare(tip.height, ControlSpec.tooltipSpec.impl.minHeight);
        compare(tip.color, Colors.inverseSurface);
        compare(findChild(tip, "tooltipText").color, Colors.inverseOnSurface);
        compare(tip.radius, 4);
        tip.text = "A rather long tooltip that says far more than a tooltip should, so it has to wrap";
        compare(tip.width, ControlSpec.tooltipSpec.impl.maxWidth, "at most 200 px wide");
        verify(tip.height > 2 * ControlSpec.tooltipSpec.impl.minHeight - 8, "it wraps: " + tip.height);
        tip.text = "Files and folders";
        const label = findChild(tip, "tooltipText");
        compare(tip.width, label.implicitWidth + 16, "the text and 8 px each side");
        const hidden = createTemporaryObject(spyComp, root, { target: tip, signalName: "hidden" });
        tip.shown = false;
        tryCompare(hidden, "count", 1, 2000, "it says when it has gone");
    }
}
