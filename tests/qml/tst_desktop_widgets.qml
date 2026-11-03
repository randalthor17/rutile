// The desktop widget grid (plan 4.4, D81): the saved data (Desktop.js), widgets drawn where they were put, scaled
// down to fit their cells, and edit mode's bar: add, remove, done.
import QtQuick
import QtTest
import qs.common
import qs.desktop
import "../qs/desktop/Desktop.js" as Desktop

TestCase {
    id: root
    name: "DesktopWidgets"
    width: 1240
    height: 800
    visible: true
    when: windowShown

    readonly property var card: ({ version: 1, name: "Card", root: { type: "card", children: [
        { type: "header", icon: "star", title: "Hello" }, { type: "stat", label: "Level", value: "42" }] } })
    readonly property var tall: ({ version: 1, name: "Tall", root: { type: "column", children:
        [1, 2, 3, 4, 5, 6, 7, 8].map(n => ({ type: "header", icon: "star", title: "Row " + n })) } })
    readonly property var specs: ({ "/w/card.json": card, "/w/tall.json": tall, "/w/broken.json": null })

    Component {
        id: comp
        DesktopWidgets {
            width: root.width
            height: root.height
            specs: root.specs
        }
    }
    function make(props) {
        const d = createTemporaryObject(comp, root, props);
        waitForRendering(d);
        return d;
    }
    function widget(d, id) { return findChild(d, "desktopWidget_" + id); }
    function settle(d) { tryVerify(() => d.grid.motion.settled, 4000, "the layout settles"); }

    // ---- Desktop.js ----
    function test_saved_layouts() {
        const all = { "DP-1": [{ id: "a", path: "/w/a.json", w: 2, h: 2 }, { id: "x" }, null], "HDMI-A-1": "junk" };
        compare(Desktop.placed(all, "DP-1").length, 1, "entries without a path are dropped");
        compare(Desktop.placed(all, "HDMI-A-1").length, 0);
        compare(Desktop.placed(null, "DP-1").length, 0);
        const both = Desktop.withScreen(all, "eDP-1", [{ id: "b", path: "/w/b.json" }, { id: "c", path: "/w/a.json" }]);
        compare(Object.keys(both).sort().join(), "DP-1,HDMI-A-1,eDP-1");
        compare(Desktop.paths(both).join(), "/w/a.json,/w/b.json", "each file once");
        compare(Object.keys(Desktop.withScreen(both, "eDP-1", [])).sort().join(), "DP-1,HDMI-A-1",
                "a screen with nothing left is left out");
        const items = [{ id: "clock", path: "/w/clock.json" }, { id: "clock-2", path: "/x/clock.json" }];
        compare(Desktop.newId(items, "/y/clock.json"), "clock-3");
        compare(Desktop.newId(items, "/y/weather.json"), "weather");
        const added = Desktop.withAdded(items, "/y/clock.json", { w: 3, h: 2 });
        compare(JSON.stringify(added[2]), JSON.stringify({ id: "clock-3", path: "/y/clock.json", w: 3, h: 2 }));
        compare(Desktop.withoutIndex(added, 1).map(i => i.id).join(), "clock,clock-3");
    }
    function test_scan_output() {
        const out = "\x1e/c/mine.json\x1f{\"version\":1,\"name\":\"Mine\"}\n" +
                    "\x1e/c/bad.json\x1f{not json" +
                    "\x1e/e/unnamed.json\x1f{\"version\":1}" +
                    "\x1e/c/mine.json\x1f{\"name\":\"Again\"}";
        compare(JSON.stringify(Desktop.scanned(out)), JSON.stringify([
            { path: "/c/mine.json", name: "Mine" }, { path: "/c/bad.json", name: "bad" },
            { path: "/e/unnamed.json", name: "unnamed" }]));
        compare(Desktop.scanned("").length, 0);
        compare(Desktop.parse("{\"a\":1}").a, 1);
        compare(Desktop.parse("[1"), null);
        compare(Desktop.parse("3"), null, "a number is no widget");
    }

    // ---- the grid ----
    function test_widgets_stay_where_they_were_put() {
        const d = make({ items: [{ id: "card", path: "/w/card.json", w: 4, h: 3, col: 6, row: 2 }] });
        settle(d);
        const w = widget(d, "card");
        verify(w, "the widget is drawn");
        const g = d.grid;
        const pitch = g.slotLayout.colW + g.gap;
        compare(g.rowHeight, g.slotLayout.colW, "square cells");
        compare(g.columns, 12);
        fuzzyCompare(w.parent.parent.x, 6 * pitch, 0.5, "at its column, with free columns before it (no gravity)");
        fuzzyCompare(w.parent.parent.y, 2 * (g.rowHeight + g.gap), 0.5, "and at its row, with free rows above");
        verify(w.host.readable);
        compare(w.host.scale, 1, "a widget that fits is not scaled");
        verify(w.host.implicitHeight < w.height - 1, "shorter than its cells");
        compare(w.host.y, 0, "and at their top, not centered");
        verify(!findChild(d, "desktopEditBar").visible, "no edit bar outside edit mode");
    }
    function test_a_tall_widget_is_scaled_down_to_fit() {
        const d = make({ items: [{ id: "tall", path: "/w/tall.json", w: 4, h: 1, col: 0, row: 0 }] });
        settle(d);
        const w = widget(d, "tall");
        verify(w.host.implicitHeight > w.height, "taller than its cell");
        verify(w.host.scale < 1);
        fuzzyCompare(w.host.implicitHeight * w.host.scale, w.height, 0.5, "all of it shows");
        verify(w.host.x > 0, "narrower then, so centered");
        compare(w.host.y, 0, "at the top of its cells");
    }
    function test_a_file_that_cannot_be_read_shows_only_while_editing() {
        const d = make({ items: [{ id: "broken", path: "/w/broken.json", w: 2, h: 2 },
                                 { id: "gone", path: "/w/gone.json", w: 2, h: 2 }] });
        const missing = id => findChild(widget(d, id), "desktopWidgetMissing").item !== null;
        verify(!missing("broken"), "nothing shown");
        d.editMode = true;
        tryVerify(() => missing("broken"), 1000, "while editing it is named, to be removed");
        verify(missing("gone"), "a file never read too");
    }

    // ---- edit mode ----
    function test_add_remove_done() {
        let saved = null;
        const d = make({ editMode: true, available: [{ path: "/w/card.json", name: "Card" }] });
        d.commitHandler = next => { saved = next; d.items = next; };
        verify(findChild(d, "desktopEditBar").visible);
        const remove = findChild(d, "desktopRemove");
        verify(!remove.enabled, "nothing to remove before something is selected");
        const asked = signalSpy.createObject(root, { target: d, signalName: "addListRequested" });
        mouseClick(findChild(d, "desktopAdd"));
        compare(asked.count, 1, "opening Add lists the files again");
        tryVerify(() => findChild(d, "desktopAddItem_0") !== null, 1000, "the menu lists what can be added");
        mouseClick(findChild(d, "desktopAddItem_0"));
        compare(saved.length, 1, "chosen: placed");
        compare(saved[0].id, "card");
        compare([saved[0].w, saved[0].h], [Desktop.NEW_SIZE.w, Desktop.NEW_SIZE.h]);
        tryCompare(d.grid, "selectedIndex", 0, 1000, "and selected, to be moved at once");
        verify(remove.enabled);
        verify(d.add("/w/card.json"));
        compare(saved[1].id, "card-2", "the same file twice gets two ids");
        tryCompare(d.grid, "selectedIndex", 1);
        d.forceActiveFocus();
        keyClick(Qt.Key_Delete);
        compare(saved.map(i => i.id).join(), "card", "Delete removes the selected one");
        compare(d.grid.selectedIndex, -1);
        const done = signalSpy.createObject(root, { target: d, signalName: "doneRequested" });
        keyClick(Qt.Key_Escape);
        compare(done.count, 1, "Escape finishes");
        mouseClick(findChild(d, "desktopDone"));
        compare(done.count, 2, "so does Done");
    }
    function test_no_room_no_add() {
        let saved = null;
        const full = [];
        for (let r = 0; r < 20; r++)
            full.push({ id: "f" + r, path: "/w/card.json", w: 12, h: 1, col: 0, row: r });
        const d = make({ editMode: true, items: full });
        const rows = d.grid.maxRows;
        d.items = full.slice(0, rows);
        d.commitHandler = next => saved = next;
        verify(!d.add("/w/card.json"), "every row taken: refused");
        compare(saved, null);
        d.items = full.slice(0, rows - 1);
        verify(d.add("/w/card.json"), "one free row: taken");
        compare(saved[rows - 1].h, 1, "shrunk to the room there is");
    }

    Component { id: signalSpy; SignalSpy {} }
}
