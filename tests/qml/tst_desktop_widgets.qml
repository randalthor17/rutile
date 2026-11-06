// The desktop widget grid (plan 4.4, D81): the saved data (Desktop.js), widgets drawn where they were put, scaled
// down to fit their cells, and edit mode's bar: add, remove, done.
import QtQuick
import QtTest
import qs.common
import qs.desktop
import "../qs/desktop/Desktop.js" as Desktop
import "../qs/widgethost/WidgetSpec.js" as Spec

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
    function test_moved_between_screens() {
        const all = { "DP-1": [{ id: "card", path: "/w/card.json", w: 4, h: 3, col: 2, row: 1 },
                               { id: "tall", path: "/w/tall.json", w: 2, h: 4, col: 8, row: 0 }],
                      "HDMI-A-1": [{ id: "card", path: "/x/card.json", w: 4, h: 3, col: 0, row: 0 }] };
        const one = Desktop.withMoved(all, "DP-1", 1, "HDMI-A-1", { w: 1, h: 3 });
        compare(one["DP-1"].map(i => i.id).join(), "card", "gone from where it was");
        compare(JSON.stringify(one["HDMI-A-1"][1]), JSON.stringify({ id: "tall", path: "/w/tall.json", w: 1, h: 3 }),
                "on the other screen at the size there, its place left for the grid to find");
        const two = Desktop.withMoved(one, "DP-1", 0, "HDMI-A-1", { w: 4, h: 3 });
        compare(Object.keys(two).join(), "HDMI-A-1", "a screen left empty is left out");
        compare(two["HDMI-A-1"].map(i => i.id).join(), "card,tall,card-2", "an id taken there gets a new one");
        const fresh = Desktop.withMoved(all, "DP-1", 0, "eDP-1", { w: 4, h: 3 });
        compare(fresh["eDP-1"].map(i => i.id).join(), "card", "a screen with nothing yet");
        compare(Desktop.withMoved(all, "DP-1", 5, "eDP-1", { w: 1, h: 1 }), all, "no such widget: unchanged");
        compare(Desktop.withMoved(all, "DP-1", 0, "DP-1", { w: 1, h: 1 }), all, "the same screen: unchanged");
    }
    function test_scan_output() {
        const out = "\x1e/c/mine.json\x1f{\"version\":1,\"name\":\"Mine\",\"size\":{\"w\":2,\"h\":5}}\n" +
                    "\x1e/c/bad.json\x1f{not json" +
                    "\x1e/e/unnamed.json\x1f{\"version\":1}" +
                    "\x1e/c/mine.json\x1f{\"name\":\"Again\"}";
        compare(JSON.stringify(Desktop.scanned(out)), JSON.stringify([
            { path: "/c/mine.json", name: "Mine", size: { w: 2, h: 5 } }, { path: "/c/bad.json", name: "bad", size: Desktop.NEW_SIZE },
            { path: "/e/unnamed.json", name: "unnamed", size: Desktop.NEW_SIZE }]), "with the size each asks for");
        compare(Desktop.scanned("").length, 0);
        compare(Desktop.parse("{\"a\":1}").a, 1);
        compare(Desktop.parse("[1"), null);
        compare(Desktop.parse("3"), null, "a number is no widget");
    }

    function test_preferred_size() {
        const p = spec => JSON.stringify(Desktop.preferredSize(spec));
        compare(p({ size: { w: 6, h: 2 } }), '{"w":6,"h":2}');
        compare(p({ size: { w: 12, h: 1 } }), '{"w":12,"h":1}');
        compare(p({}), '{"w":4,"h":3}', "none: the usual");
        compare(p(null), '{"w":4,"h":3}');
        compare(p({ size: { w: 0, h: 2 } }), '{"w":4,"h":3}', "out of range");
        compare(p({ size: { w: 13, h: 2 } }), '{"w":4,"h":3}');
        compare(p({ size: { w: 2.5, h: 2 } }), '{"w":4,"h":3}', "whole cells only");
        compare(p({ size: { w: "2", h: 2 } }), '{"w":4,"h":3}');
        compare(p({ size: [2, 2] }), '{"w":4,"h":3}');
        Desktop.preferredSize({}).w = 9;
        compare(Desktop.NEW_SIZE.w, 4, "a copy, never the default itself");
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
        compare(w.host.height, w.height, "filling them: made taller, the widget grows down (D83)");
        verify(!findChild(d, "desktopEditBar").visible, "no edit bar outside edit mode");
    }
    function test_a_tall_widget_is_scaled_down_to_fit() {
        const d = make({ items: [{ id: "tall", path: "/w/tall.json", w: 4, h: 1, col: 0, row: 0 }] });
        settle(d);
        const w = widget(d, "tall");
        verify(w.host.implicitHeight > w.height, "taller than its cell");
        verify(w.host.scale < 1);
        compare(w.inset, Spacing.lg, "no card at its root: a margin from the cell's edges (D84)");
        fuzzyCompare(w.host.implicitHeight * w.host.scale, w.height - 2 * w.inset, 0.5, "all of it shows, inside it");
        verify(w.host.x > 0, "narrower then, so centered");
        fuzzyCompare(w.host.y, w.inset, 0.5, "at the margin");
    }
    // D84: text scales with the widget's size, what cannot stretch is centered
    readonly property var bare: ({ version: 1, name: "Bare", root: { type: "row", children: [
        { type: "stat", value: "2:22" }, { type: "chip", label: "Tue" }] } })
    function test_centered_and_scaled() {
        const d = make({ specs: Object.assign({ "/w/bare.json": bare }, specs), items: [
            { id: "bare", path: "/w/bare.json", w: 4, h: 3, col: 0, row: 0 },
            { id: "big", path: "/w/card.json", w: 8, h: 6, col: 4, row: 0 },
            { id: "small", path: "/w/card.json", w: 2, h: 2, col: 0, row: 4 },
            { id: "wide", path: "/w/bare.json", w: 8, h: 3, col: 0, row: 7 }] });
        settle(d);
        compare(widget(d, "big").textScale, 1, "text scaling is off by default: a big widget's text as designed");
        d.scaleText = true;
        const b = widget(d, "bare");
        compare(b.textScale, 1, "a new widget's size: text as designed");
        verify(!b.host.stretches);
        fuzzyCompare(b.host.y + b.host.height / 2, b.height / 2, 1, "cannot stretch: centered in its cells");
        compare(b.host.height, b.host.implicitHeight);
        const big = widget(d, "big");
        compare(big.textScale, 2, "twice the size: twice the text");
        compare(big.inset, 0, "a card brings its own padding");
        verify(Spec.surfaced({ type: "column", children: [{ type: "row", children: [{ type: "card", children: [] }] }] }),
               "so does a card alone in a column (the examples)");
        verify(!Spec.surfaced({ type: "column", children: [{ type: "header", title: "t" }, { type: "card", children: [] }] }),
               "but not with text beside it");
        compare(big.host.height, big.height, "and fills its cells");
        const value = texts(big).find(t => t.text === "42");
        compare(value.font.pixelSize, Math.round(Type.displaySmall.size * 2));
        compare(widget(d, "small").textScale, 0.8, "smaller: down to 0.8");
        compare(widget(d, "wide").textScale, 1, "wider only: the smaller ratio counts");
        // every container passes the scale on: a column, then a row
        const nested = { version: 1, name: "N", root: { type: "column", children: [{ type: "row", children: [
            { type: "stat", value: "7" }] }] } };
        const e = make({ scaleText: true, specs: { "/w/n.json": nested }, items: [{ id: "n", path: "/w/n.json", w: 8, h: 6 }] });
        settle(e);
        compare(texts(widget(e, "n")).find(t => t.text === "7").font.pixelSize, Math.round(Type.displaySmall.size * 2));
        // a widget that asks for 8 by 6 draws its text as designed there (D134)
        const asks = Object.assign({ size: { w: 8, h: 6 } }, nested);
        const f = make({ scaleText: true, specs: { "/w/a.json": asks }, items: [{ id: "a", path: "/w/a.json", w: 8, h: 6 }] });
        settle(f);
        compare(widget(f, "a").textScale, 1, "its own size: text as designed");
    }
    function texts(item, out) {
        out = out ?? [];
        if (item.text !== undefined && item.font !== undefined) out.push(item);
        for (const c of item.children) texts(c, out);
        return out;
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

    // D86: a right-click on a widget asks to edit, with it selected; the window takes the pointer only on the widgets
    function test_right_click_edits_and_input_rects() {
        const d = make({ items: [{ id: "a", path: "/w/card.json", w: 4, h: 3, col: 0, row: 0 },
                                 { id: "b", path: "/w/card.json", w: 2, h: 2, col: 6, row: 1 }] });
        settle(d);
        const asked = signalSpy.createObject(root, { target: d, signalName: "editRequested" });
        const pressed = signalSpy.createObject(root, { target: d, signalName: "pressed" });
        mouseClick(widget(d, "b"), 10, 10, Qt.LeftButton);
        compare(asked.count, 0, "a left click asks nothing");
        compare(pressed.count, 1, "but closes the shell's popups (D90)");
        mouseClick(widget(d, "b"), 10, 10, Qt.RightButton);
        compare(asked.count, 1);
        compare(pressed.count, 2);
        compare(asked.signalArguments[0][0], 1, "the widget right-clicked");
        d.editMode = true;
        d.select(1);
        compare(d.grid.selectedIndex, 1, "and selected");
        mouseClick(widget(d, "b"), 10, 10, Qt.RightButton);
        compare(asked.count, 1, "while editing, a right-click asks nothing more");
        const rects = d.inputRects;
        compare(rects.length, 2);
        const b = widget(d, "b").mapToItem(d, 0, 0);
        compare([rects[1].x, rects[1].y, rects[1].width, rects[1].height],
                [b.x, b.y, widget(d, "b").width, widget(d, "b").height], "each widget's cells, in the window");
    }

    // ---- edit mode ----
    function test_add_remove_done() {
        let saved = null;
        const d = make({ editMode: true, available: [{ path: "/w/card.json", name: "Card", size: { w: 6, h: 2 } }] });
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
        compare([saved[0].w, saved[0].h], [6, 2], "at the size it asks for (D134)");
        tryCompare(d.grid, "selectedIndex", 0, 1000, "and selected, to be moved at once");
        verify(remove.enabled);
        verify(d.add("/w/card.json"));
        compare(saved[1].id, "card-2", "the same file twice gets two ids");
        compare([saved[1].w, saved[1].h], [Desktop.NEW_SIZE.w, Desktop.NEW_SIZE.h], "no size given: the usual");
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

    function test_move_to_another_screen() {
        const d = make({ editMode: true, items: [{ id: "card", path: "/w/card.json", w: 4, h: 3, col: 0, row: 0 },
                                                 { id: "tall", path: "/w/tall.json", w: 2, h: 4, col: 6, row: 0 }] });
        const move = findChild(d, "desktopMove");
        verify(!move.visible, "one screen: nothing to move to");
        d.screens = [{ name: "HDMI-A-1", label: "Dell (HDMI-A-1)" }, { name: "DP-2", label: "DP-2" }];
        d.roomOn = (name, item) => name === "DP-2" ? null : { w: item.w, h: item.h };
        verify(move.visible);
        waitForItemPolished(move.parent);       // the bar's row places it beside Remove
        verify(!move.enabled, "nothing selected");
        d.select(1);
        verify(move.enabled);
        const asked = signalSpy.createObject(root, { target: d, signalName: "moveRequested" });
        mouseClick(move);
        tryVerify(() => findChild(d, "desktopMoveItem_HDMI-A-1") !== null, 1000, "the other screens are listed");
        verify(d.moveOpen);
        const full = findChild(d, "desktopMoveItem_DP-2");
        verify(!full.enabled, "a screen without room is greyed out");
        mouseClick(findChild(d, "desktopMoveItem_HDMI-A-1"));
        compare(asked.count, 1, "chosen: asked to move");
        compare(asked.signalArguments[0][0], 1, "the selected widget");
        compare(asked.signalArguments[0][1], "HDMI-A-1", "to that screen");
        tryVerify(() => !d.moveOpen, 1000, "the menu closes");
        compare(d.grid.selectedIndex, -1, "nothing selected after");
        verify(!move.enabled);
        d.select(0);
        mouseClick(move);
        tryVerify(() => d.moveOpen);
        d.forceActiveFocus();
        const done = signalSpy.createObject(root, { target: d, signalName: "doneRequested" });
        keyClick(Qt.Key_Escape);
        tryVerify(() => !d.moveOpen, 1000, "Escape closes the menu first");
        compare(done.count, 0);
        mouseClick(move);
        tryVerify(() => d.moveOpen);
        d.select(-1);
        tryVerify(() => !d.moveOpen, 1000, "and losing the selection closes it");
    }

    Component { id: signalSpy; SignalSpy {} }
}
