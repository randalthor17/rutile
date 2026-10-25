import QtQuick
import QtTest
import qs.common
import qs.components

// EditableGrid: packing (positions, clamping, gravity), delegates kept across changes, and edit mode (select, drag,
// resize) with commits that go through the owner.
TestCase {
    id: root
    name: "EditableGrid"
    width: 800
    height: 600
    visible: true
    when: windowShown

    property int created: 0

    Component {
        id: cellComp
        Rectangle {
            property var modelData
            property int index: -1
            property int clicks: 0
            color: Colors.primary
            Component.onCompleted: root.created++
            MouseArea { anchors.fill: parent; onClicked: parent.clicks++ }
        }
    }
    Component {
        id: gridComp
        EditableGrid {
            x: 20; y: 20
            width: 406                      // 4 columns of 100 with 2 px gaps
            columns: 4
            gap: 2
            rowHeight: 50
            delegate: cellComp
        }
    }

    function init() { created = 0; }
    function cleanup() { mouseMove(root, 790, 590); }

    function make(props) { return createTemporaryObject(gridComp, root, props || {}); }
    function four() {
        return [{ id: "a", w: 2, h: 1 }, { id: "b", w: 1, h: 1 }, { id: "c", w: 1, h: 1 }, { id: "d", w: 1, h: 1 }];
    }
    // The grid's slots in item order (they are the children that carry an `entry`).
    function slotsOf(g) {
        var out = [];
        for (var i = 0; i < g.children.length; i++)
            if (g.children[i].entry !== undefined) out.push(g.children[i]);
        out.sort(function (a, b) { return a.index - b.index; });
        return out;
    }
    function cellOf(g, id) {
        for (var i = 0; i < g.items.length; i++)
            if (g.items[i].id === id) return g.slotLayout.slots[i];
        return null;
    }
    function settle(g) {
        tryVerify(function () { return g.motion.settled; }, 4000, "the layout motion settles");
    }
    // A pointer pressed on slot `s` at (x, y); moves are offsets from there in fixed (TestCase) coordinates,
    // since the slot itself moves while it is dragged.
    function press(s, x, y) {
        var start = s.mapToItem(root, x, y);
        mousePress(root, start.x, start.y);
        return {
            to: function (dx, dy, steps) {
                var from = this.at || { x: 0, y: 0 };
                var n = steps || 4;
                for (var k = 1; k <= n; k++)
                    mouseMove(root, start.x + from.x + (dx - from.x) * k / n, start.y + from.y + (dy - from.y) * k / n);
                this.at = { x: dx, y: dy };
            },
            release: function () {
                var at = this.at || { x: 0, y: 0 };
                mouseRelease(root, start.x + at.x, start.y + at.y);
            }
        };
    }
    // Drag slot `s` by (dx, dy) in steps, as a pointer would.
    function drag(s, dx, dy) {
        var p = press(s, s.width / 2, s.height / 2);
        p.to(dx, dy, 8);
        p.release();
    }

    function test_packs_in_order_and_sizes_cells() {
        var g = make({ items: four() });
        var s = g.slotLayout.slots;
        compare([s[0].col, s[0].row, s[0].cols], [0, 0, 2]);
        compare([s[1].col, s[1].row], [2, 0]);
        compare([s[2].col, s[2].row], [3, 0]);
        compare([s[3].col, s[3].row], [0, 1]);
        compare(s[0].w, 202, "two columns and the gap between them");
        compare(s[3].y, 52);
        compare(g.implicitHeight, 102);
        var shown = slotsOf(g);
        compare(shown.length, 4);
        compare([shown[3].x, shown[3].y, shown[3].width], [0, 52, 100], "slots start at their cells, unanimated");
        verify(g.motion.settled, "nothing moves on the first layout");
    }

    function test_sizes_are_clamped_to_columns_and_item_limits() {
        var g = make({ items: [{ id: "wide", w: 9, h: 1 }, { id: "lim", w: 3, h: 5, maxW: 2, maxH: 2 },
                               { id: "min", w: 1, h: 1, minW: 2 }] });
        compare(g.slotLayout.slots[0].cols, 4);
        compare([g.slotLayout.slots[1].cols, g.slotLayout.slots[1].rows], [2, 2]);
        compare(g.slotLayout.slots[2].cols, 2);
        var capped = make({ items: [{ id: "tall", w: 1, h: 6 }], maxRows: 3 });
        compare(capped.slotLayout.slots[0].rows, 3, "maxRows caps an item's height");
    }

    function test_saved_positions_and_gravity() {
        var saved = [{ id: "a", w: 1, h: 1, col: 2, row: 3 }, { id: "b", w: 1, h: 1, col: 2, row: 3 }];
        var g = make({ items: saved, gravity: false });
        compare([g.slotLayout.slots[0].col, g.slotLayout.slots[0].row], [2, 3], "kept where it was saved");
        compare(g.slotLayout.slots[1].row, 4, "a clash settles downward");
        var up = make({ items: saved });
        compare([up.slotLayout.slots[0].col, up.slotLayout.slots[0].row], [2, 0], "gravity pulls into the hole");
        compare(up.slotLayout.slots[1].row, 1);
    }

    function test_delegates_are_kept_across_changes() {
        var g = make({ items: four() });
        compare(created, 4);
        var first = slotsOf(g)[0].children[0].item;
        compare(first.modelData.id, "a");
        var next = four().reverse();
        next[3].w = 1;
        g.items = next;
        compare(created, 4, "a reorder and a resize create nothing");
        compare(first.modelData.id, "a", "a delegate keeps its item");
        compare(first.index, 3, "and learns its new index");
        g.items = next.concat([{ id: "e" }]);
        compare(created, 5, "only the new item is created");
        g.items = [{ id: "e" }];
        compare(slotsOf(g).length, 1, "removed items go");
    }

    function test_outside_edit_mode_the_delegates_get_the_input() {
        var g = make({ items: four() });
        var s = slotsOf(g)[1];
        mouseClick(s);
        compare(s.children[0].item.clicks, 1);
        drag(s, -150, 60);
        compare(g.items[1].col, undefined, "nothing moves outside edit mode");
        compare(g.selectedIndex, -1);
    }

    function test_click_selects_and_leaving_edit_mode_clears() {
        var g = make({ items: four(), editMode: true });
        var s = slotsOf(g)[2];
        mouseClick(s);
        compare(g.selectedIndex, 2);
        compare(s.children[0].item.clicks, 0, "edit mode takes the click, not the delegate");
        g.editMode = false;
        compare(g.selectedIndex, -1);
    }

    function test_drag_moves_an_item_and_the_rest_make_room() {
        var committed = null;
        var g = make({ items: four(), editMode: true });
        g.commitHandler = function (next) { committed = next; g.items = next; };
        for (var round = 0; round < 2; round++) {
            var d = slotsOf(g)[3];                // d, 1x1 at (0, 1) to (3, 0) and back
            committed = null;
            var to = round === 0 ? [3, 0] : [0, 1];
            var from = [g.slotLayout.slots[3].col, g.slotLayout.slots[3].row];
            drag(d, (to[0] - from[0]) * 102, (to[1] - from[1]) * 52);
            verify(committed !== null, "a move commits, round " + round);
            compare([committed[3].col, committed[3].row], to, "d lands where it was dropped");
            settle(g);
            compare([d.x, d.y], [to[0] * 102, to[1] * 52], "and is shown there");
        }
        compare(cellOf(g, "c").row, 0, "c is back on the first row");
        var tooShort = slotsOf(g)[1];
        committed = null;
        var p = press(tooShort, 50, 25);
        p.to(1, 1, 1);
        compare(g.draggingIndex, -1, "a move below the drag threshold starts no drag");
        p.release();
        compare(committed, null, "it is a click, not a move");
        compare(g.selectedIndex, 1);
        var back = slotsOf(g)[2];
        p = press(back, 50, 25);
        p.to(-102, 0);
        compare(g.dragCell.col, 2);
        p.to(0, 0);
        verify(g.draggingIndex === 2);
        p.release();
        compare(committed, null, "dropped where it started: nothing to commit");
    }

    function test_drag_shows_a_placeholder_and_holds_the_height() {
        var g = make({ items: four(), editMode: true });
        var d = slotsOf(g)[3];
        var p = press(d, 50, 25);
        p.to(306, -52, 8);
        verify(g.draggingIndex === 3);
        compare([g.dragCell.col, g.dragCell.row], [3, 0]);
        var placeholder = g.children[0].item;
        verify(placeholder && placeholder.visible, "the drop target is shown");
        verify(g.height >= 102, "the grid does not shrink under the pointer");
        p.release();
        compare(g.draggingIndex, -1);
        verify(!g.children[0].item, "the placeholder goes with the drag");
    }

    function test_the_height_holds_while_dragging() {
        var g = make({ items: four(), editMode: true, gravity: false });
        var d = slotsOf(g)[3];
        var p = press(d, 50, 25);
        p.to(0, 52);
        compare(g.dragCell.row, 2);
        compare(g.height, 154, "a third row while d hangs below");
        p.to(0, 0);
        compare(g.dragCell.row, 1);
        compare(g.height, 154, "and it stays until the drop");
        p.release();
        compare(g.height, 102);
    }

    function test_a_refused_commit_springs_back() {
        var g = make({ items: four(), editMode: true });
        g.commitHandler = function (next) { };     // the owner does not apply it
        var d = slotsOf(g)[3];
        drag(d, 306, -52);
        compare(cellOf(g, "d").row, 1, "the layout stays what the items say");
        settle(g);
        compare([d.x, d.y], [0, 52], "and the item returns");
    }

    function test_resize_handle_changes_the_width_within_limits() {
        var items = four();
        items[0].minW = 1; items[0].maxW = 2;
        var committed = null;
        var g = make({ items: items, editMode: true });
        g.commitHandler = function (next) { committed = next; g.items = next; };
        var a = slotsOf(g)[0];
        mouseClick(a);
        compare(g.selectedIndex, 0);
        // The handle sits on the right edge; drag it one column left.
        var p = press(a, a.width - 1, 25);
        p.to(-102, 0, 8);
        compare(g.sizePreview.changes.w, 1, "previews the narrower size");
        p.release();
        compare(committed[0].w, 1);
        settle(g);
        compare(a.width, 100);
        // Back out past its maximum: it stops at 2.
        p = press(a, a.width - 1, 25);
        p.to(306, 0, 8);
        p.release();
        compare(committed[0].w, 2, "maxW holds");
        committed = null;
        p = press(a, a.width - 1, 25);
        p.to(-20, 0);
        p.release();
        compare(committed, null, "a resize that ends at the same size commits nothing");
        var fixed = slotsOf(g)[1];
        mouseClick(fixed);
        compare(g.selectedIndex, 1);
        p = press(fixed, fixed.width - 1, 25);
        p.to(120, 0);
        p.release();
        compare(g.sizePreview, null, "an item with no maximum has no handle");
        compare(cellOf(g, "b").cols, 1);
    }

    function test_max_rows_limits_resizes_and_new_items() {
        var full = [{ id: "a", w: 4 }, { id: "b", w: 2 }, { id: "c", w: 2 }];
        var g = make({ items: full, maxRows: 2 });
        compare(g.fitNew({ id: "x", w: 1 }), null, "no room for another");
        var roomy = make({ items: [{ id: "a", w: 4 }, { id: "b", w: 2 }], maxRows: 2 });
        compare(roomy.fitNew({ id: "x", w: 4, minW: 1 }), { w: 2, h: 1 }, "a new item shrinks to fit");
        var r = make({ items: [{ id: "a", w: 2, maxW: 4 }, { id: "b", w: 2 }, { id: "c", w: 4 }], maxRows: 2,
                       editMode: true });
        r.previewResize(0, 406, 50);
        compare(r.sizePreview.changes.w, 2, "growing to 3 or 4 would need a third row; it stays at 2");
    }

    function test_uncontrolled_grid_keeps_changes_itself() {
        var g = make({ items: four(), editMode: true });
        drag(slotsOf(g)[3], 306, -52);
        compare([cellOf(g, "d").col, cellOf(g, "d").row], [3, 0]);
        compare(g.items[3].col, 3, "the saved items carry positions");
    }

    function test_layout_changes_move_on_the_shared_spring() {
        var g = make({ items: four() });
        wait(50);                                   // past the first frame, so changes animate
        var b = slotsOf(g)[1];
        g.items = [{ id: "b" }, { id: "a", w: 2 }, { id: "c" }, { id: "d" }];
        verify(!g.motion.settled, "a change animates");
        compare(b.x, 204, "starting from where it was");
        settle(g);
        compare(b.x, 0, "and ends at its new cell");
    }
}
