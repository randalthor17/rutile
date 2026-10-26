import QtQuick
import QtTest
import qs.common
import qs.shelf
import "../qs/shelf/ShelfApps.js" as ShelfApps

TestCase {
    id: root
    name: "Shelf"
    width: 800
    height: 200
    visible: true
    when: windowShown

    Component { id: shelfComp; Shelf { width: 800 } }
    Component { id: spyComp; SignalSpy {} }

    readonly property var files: ({ id: "org.gnome.Nautilus", name: "Files", icon: "org.gnome.Nautilus", startupClass: "" })
    readonly property var firefox: ({ id: "firefox", name: "Firefox", icon: "firefox", startupClass: "firefox" })
    readonly property var gimp: ({ id: "gimp", name: "GIMP", icon: "gimp", startupClass: "Gimp-2.10" })

    function test_pins() {
        compare(ShelfApps.pins("", id => ["thunar", "firefox", "chromium", "kitty"].indexOf(id) >= 0).join(),
                "thunar,firefox,kitty", "the first installed app of each group");
        compare(ShelfApps.pins("", id => false).length, 0);
        compare(ShelfApps.pins(" a, b ,,c", id => false).join(), "a,b,c", "an override wins, as given");
    }

    function test_matching_windows_to_apps() {
        verify(ShelfApps.matches(firefox, "firefox"));
        verify(ShelfApps.matches(firefox, "Firefox"), "case does not matter");
        verify(ShelfApps.matches(files, "org.gnome.Nautilus"));
        verify(ShelfApps.matches(files, "nautilus"), "the last part of a reverse-DNS id");
        verify(ShelfApps.matches(gimp, "gimp-2.10"), "the startup class");
        verify(!ShelfApps.matches(firefox, "foot"));
        verify(!ShelfApps.matches(firefox, ""), "a window without an app id matches nothing");
        verify(ShelfApps.matches({ id: "foot.desktop", startupClass: "" }, "foot"), "a .desktop suffix is ignored");
    }

    function test_build() {
        var lookup = appId => appId === "gimp-2.10" ? gimp : null;
        var windows = [
            { appId: "firefox", activated: false },
            { appId: "gimp-2.10", activated: true },
            { appId: "firefox", activated: false },
            { appId: "mystery", activated: false },
            { appId: "gimp-2.10", activated: false }
        ];
        var items = ShelfApps.build([files, firefox], windows, lookup);
        compare(items.map(i => i.id).join(), "org.gnome.Nautilus,firefox,gimp,mystery", "pinned, then running in order");
        compare(items.map(i => i.pinned).join(), "true,true,false,false");
        verify(!items[0].running, "Files is pinned but not running");
        verify(items[1].running && !items[1].active);
        compare(items[1].windows.join(), "0,2", "both Firefox windows");
        verify(items[2].running && items[2].active, "GIMP has the active window");
        compare(items[2].windows.join(), "1,4", "grouped under one app");
        compare(items[3].name, "mystery", "no entry: shown by its app id");
        compare(items[3].icon, "");
        compare(ShelfApps.build([], [], lookup).length, 0);
    }

    function test_next_window_cycles() {
        var windows = [{ activated: false }, { activated: true }, { activated: false }];
        compare(ShelfApps.nextWindow({ windows: [0, 1, 2] }, windows), 2, "the one after the active window");
        compare(ShelfApps.nextWindow({ windows: [0, 2] }, windows), 0, "none active: the first");
        compare(ShelfApps.nextWindow({ windows: [2, 1] }, windows), 2, "wraps around");
        compare(ShelfApps.nextWindow({ windows: [] }, windows), -1);
    }

    function test_shelf_shows_items() {
        var items = ShelfApps.build([files, firefox], [{ appId: "firefox", activated: true }, { appId: "gimp-2.10" }],
                                    appId => gimp).map(it => Object.assign(it, { icon: "" }));
        var shelf = createTemporaryObject(shelfComp, root, { items: items });
        waitForRendering(shelf);
        var opened = createTemporaryObject(spyComp, root, { target: shelf, signalName: "opened" });
        var launcher = createTemporaryObject(spyComp, root, { target: shelf, signalName: "launcherClicked" });
        compare(shelf.height, Spacing.xxxl + Spacing.sm);
        verify(findChild(shelf, "shelfDivider").visible, "a divider before the running unpinned app");
        var ff = findChild(shelf, "shelfApp_firefox");
        var fm = findChild(shelf, "shelfApp_org.gnome.Nautilus");
        var gp = findChild(shelf, "shelfApp_gimp");
        verify(ff && fm && gp);
        verify(fm.x < ff.x && ff.x < gp.x, "in order");
        verify(!findChild(fm, "shelfRunningMark").visible, "not running: no mark");
        var mark = findChild(ff, "shelfRunningMark");
        verify(mark.visible);
        tryCompare(mark, "width", Spacing.lg, 2000, "active: the long mark");
        verify(Qt.colorEqual(mark.color, Colors.primary));
        compare(findChild(gp, "shelfRunningMark").width, Spacing.xs, "running: a dot");
        var fallback = findChild(fm, "shelfFallbackIcon");
        verify(fallback.visible, "no icon: the app's initial");
        compare(fallback.children[0].text, "F");
        mouseClick(ff, ff.width / 2, ff.height / 2);
        compare(opened.count, 1);
        compare(opened.signalArguments[0][0].id, "firefox");
        var l = findChild(shelf, "shelfLauncher");
        mouseClick(l, l.width / 2, l.height / 2);
        compare(launcher.count, 1);
        // only pinned apps: no divider
        shelf.items = items.filter(i => i.pinned);
        verify(!findChild(shelf, "shelfDivider").visible);
    }

    function test_press_shrinks_and_springs_back() {
        var shelf = createTemporaryObject(shelfComp, root, { items: [{ id: "a", name: "A", icon: "", pinned: true,
                                                                       running: false, active: false, windows: [] }] });
        waitForRendering(shelf);
        var b = findChild(shelf, "shelfApp_a");
        var face = b.children[0];
        mousePress(b, b.width / 2, b.height / 2);
        tryVerify(function () { return face.scale < 0.95; }, 2000, "pressed: smaller");
        mouseRelease(b, b.width / 2, b.height / 2);
        tryCompare(face, "scale", 1, 2000, "released: back");
    }
}
