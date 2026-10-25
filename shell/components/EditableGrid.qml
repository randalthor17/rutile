// A grid of items that are saved data ({id, w, h} in cells, plus the col and row they were placed at), shared by
// Quick Settings tiles and the desktop widget grid (D17). `delegate` draws one item; it gets `modelData` and `index`
// if it declares them. In `editMode` an item is selected by a click and moved by dragging; the selected one shows a
// resize handle on each side it can move (Googlebook's "Edit tiles"). Neighbors in the way of a resize shrink, and
// move away only when they would have to go below their minimum. Changes go to `commitHandler(items)`; with none,
// the grid keeps them itself (demos). Every item can grow to the full width and to `maxRows` (0 for no limit)
// unless it sets minW/maxW/minH/maxH. Columns follow LayoutMirroring, so a right-to-left session mirrors the grid.
//
// Light on memory (D31): delegates are kept across reorders (a ListModel keyed by id), the edit chrome exists only
// in edit mode, and one spring per grid moves every item (each lerps from where it was to where it goes).
// Packing is GridLayout.js, ported from DankMaterialShell (MIT).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import "GridLayout.js" as GridLayout

Item {
    id: root

    property var items: []
    property int columns: 4
    property real rowHeight: ControlSpec.tileSpec.tileHeight
    property real gap: ControlSpec.tileSpec.tileArrangementPadding
    property int maxRows: 0
    property bool gravity: true             // pull items up into holes (Quick Settings); off keeps them where put
    property bool editMode: false
    property Component delegate: null
    property real slotRadius: Shapes.extraLarge    // for the selection outline and the drop placeholder
    property var commitHandler: null        // a callback, not a signal: Qt 6.12 hands signal arrays over as sequences
    property int selectedIndex: -1

    property int draggingIndex: -1
    property var dragCell: null
    property int resizingIndex: -1
    property var resizeItems: null          // every item as the resize under way leaves it, or null for no change
    property var pinnedCells: null          // where everything was when the interaction began
    property real heldHeight: 0

    readonly property bool mirrored: LayoutMirroring.enabled
    readonly property bool interacting: draggingIndex >= 0 || resizingIndex >= 0
    readonly property int interactingIndex: draggingIndex >= 0 ? draggingIndex : resizingIndex
    // The item being moved or resized is placed first, so it gets the cell it asks for and the rest make room.
    readonly property var placementOrder: {
        const order = items.map((item, i) => i);
        if (interactingIndex < 0)
            return order;
        order.splice(interactingIndex, 1);
        order.unshift(interactingIndex);
        return order;
    }
    readonly property var clampedItems: items.map(item => Object.assign({}, item, clampSize(item, item.w, item.h)))
    readonly property var pinnedItems: pinnedCells ? GridLayout.placedItems(clampedItems, pinnedCells) : clampedItems
    readonly property var layoutItems: {
        if (resizeItems)
            return resizeItems;
        if (draggingIndex < 0 || !dragCell)
            return pinnedItems;
        const changed = pinnedItems.map((item, i) => i === draggingIndex ? Object.assign({}, item, dragCell) : item);
        return gravity ? GridLayout.dropInto(changed, pinnedCells, draggingIndex, dragCell, trial => pack(trial).cells)
                       : changed;
    }
    readonly property var slotLayout: GridLayout.packCards(layoutItems, placementOrder, columns, width, gap, rowHeight,
                                                           null, gravity, mirrored)
    // The height holds while an interaction is under way, so the grid does not jump under the pointer.
    readonly property real layoutHeight: interacting ? Math.max(heldHeight, slotLayout.totalHeight) : slotLayout.totalHeight
    readonly property alias motion: motion  // exposed for tests

    implicitHeight: layoutHeight

    function limits(item) {
        const minW = Math.max(1, item.minW || 1);
        const minH = Math.max(1, item.minH || 1);
        return {
            minW: Math.min(minW, columns),
            maxW: Math.max(Math.min(minW, columns), Math.min(columns, item.maxW || columns)),
            minH: minH,
            maxH: Math.max(minH, item.maxH || (maxRows > 0 ? maxRows : Infinity))
        };
    }
    function clampSize(item, w, h) {
        const l = limits(item);
        return {
            w: Math.max(l.minW, Math.min(l.maxW, Math.round(w || l.minW))),
            h: Math.max(l.minH, Math.min(l.maxH, Math.round(h || l.minH)))
        };
    }
    function pack(trial) {
        return GridLayout.packCells(trial, placementOrder, columns, null, gravity);
    }
    // Whether a layout stays under maxRows (or under what `base` already uses, if that is more).
    function fits(trial, base) {
        if (maxRows <= 0)
            return true;
        return pack(trial).rows <= Math.max(maxRows, pack(base).rows);
    }

    function pin() {
        pinnedCells = slotLayout.slots.slice();
        heldHeight = slotLayout.totalHeight;
    }
    function cancelInteraction() {
        draggingIndex = -1;
        dragCell = null;
        resizingIndex = -1;
        resizeItems = null;
        pinnedCells = null;
        heldHeight = 0;
    }
    function committedItems() {
        return GridLayout.placedItems(layoutItems, slotLayout.slots);
    }
    function commit(next) {
        if (commitHandler)
            commitHandler(next);
        else
            items = next;
    }

    function beginDrag(index) {
        if (!editMode || interacting || !items[index])
            return false;
        pin();
        selectedIndex = index;
        draggingIndex = index;
        return true;
    }
    // (x, y): the dragged item's top-left corner in the grid.
    function updateDragTarget(x, y) {
        const slot = slotLayout.slots[draggingIndex];
        if (!slot)
            return;
        const cell = GridLayout.cellAt(slotLayout, x, y, slot.cols, slot.rows);
        const lastRow = maxRows > 0 ? Math.max(maxRows, slotLayout.rows) - slot.rows : slotLayout.rows;
        cell.row = Math.min(cell.row, Math.max(0, lastRow));
        if (dragCell && dragCell.col === cell.col && dragCell.row === cell.row)
            return;
        dragCell = cell;
    }
    function endDrag() {
        if (draggingIndex < 0)
            return;
        const next = committedItems();
        const moved = pinnedCells.some((cell, i) => cell && (cell.col !== next[i].col || cell.row !== next[i].row));
        cancelInteraction();
        if (moved)
            commit(next);
    }

    // ---- resizing, one edge at a time ----
    // Every item where it is now, with its col and row (the pinned layout while an interaction is under way).
    function placedNow() {
        return pinnedCells ? pinnedItems : GridLayout.placedItems(clampedItems, slotLayout.slots);
    }
    // Item `index` with `edge` ("start", "end", "top", "bottom") moved outward by `growth` cells, as the grid would
    // take it: null if it cannot move that far or the result would outgrow maxRows.
    function resized(base, index, edge, growth) {
        const next = GridLayout.resizeEdge(base, index, edge, growth, item => limits(item), columns);
        return next && fits(next, base) ? next : null;
    }
    // Whether the edge can move at all: outward (room, or neighbors that shrink or move) or inward (above minimum).
    function canResize(index, edge) {
        if (!editMode || !items[index])
            return false;
        const base = placedNow();
        return resized(base, index, edge, 1) !== null || resized(base, index, edge, -1) !== null;
    }
    // Move an edge of item `index` by `growth` cells (fractional from a pointer; rounded). Takes the largest move
    // toward it that fits.
    function previewResize(index, edge, growth) {
        if (!editMode || draggingIndex >= 0 || (resizingIndex >= 0 && resizingIndex !== index) || !items[index])
            return;
        if (!pinnedCells)
            pin();
        resizingIndex = index;
        let next = null;
        for (let d = Math.round(growth); d !== 0 && !next; d -= Math.sign(d))
            next = resized(pinnedItems, index, edge, d);
        if (JSON.stringify(next) !== JSON.stringify(resizeItems))
            resizeItems = next;
    }
    function commitResize() {
        if (resizingIndex < 0)
            return;
        const changed = resizeItems !== null;
        const next = committedItems();
        cancelInteraction();
        if (changed)
            commit(next);
    }

    // Whether an item of this size would fit under maxRows (for an "add" action), and the size it would get.
    function fitNew(item) {
        const l = limits(item);
        return GridLayout.fitNew(clampedItems, columns, maxRows, Object.assign({}, item, clampSize(item, item.w, item.h)),
                                 { w: l.minW, h: l.minH });
    }

    // ---- delegates kept across reorders ----
    function keysFor(list) {
        const seen = {};
        return list.map(item => {
            const base = String(item.id ?? "");
            const count = seen[base] || 0;
            seen[base] = count + 1;
            return base + "#" + count;
        });
    }
    function syncSlots() {
        const selectedKey = selectedIndex >= 0 && selectedIndex < slots.count ? slots.get(selectedIndex).key : "";
        const keys = keysFor(items);
        for (let i = slots.count - 1; i >= 0; i--) {
            if (keys.indexOf(slots.get(i).key) < 0)
                slots.remove(i);
        }
        for (let p = 0; p < keys.length; p++) {
            const json = JSON.stringify(items[p]);
            let current = -1;
            for (let j = p; j < slots.count; j++) {
                if (slots.get(j).key === keys[p]) {
                    current = j;
                    break;
                }
            }
            if (current < 0) {
                slots.insert(p, { key: keys[p], json: json });
                continue;
            }
            if (current !== p)
                slots.move(current, p, 1);
            if (slots.get(p).json !== json)
                slots.setProperty(p, "json", json);
        }
        selectedIndex = keys.indexOf(selectedKey);
        retarget();
    }

    // ---- motion: every slot lerps from where it was shown to its cell, on one shared spring ----
    property bool animateLayout: false
    function retarget() {
        let changed = false;
        const next = [];
        for (let i = 0; i < repeater.count; i++) {
            const slot = repeater.itemAt(i) as GridSlot;
            const cell = slot ? slotLayout.slots[slot.index] : null;
            next.push(cell ? { x: cell.x, y: cell.y, w: cell.w, h: cell.h } : null);
            if (slot && cell && (!slot.to || !GridLayout.sameRect(slot.to, next[i])))
                changed = true;
        }
        if (!changed)
            return;
        const animate = animateLayout && width > 0;
        for (let i = 0; i < repeater.count; i++) {
            const slot = repeater.itemAt(i) as GridSlot;
            if (!slot || !next[i])
                continue;
            slot.from = animate && slot.to ? slot.shown() : next[i];
            slot.to = next[i];
        }
        if (animate) {
            motion.snap(0);
            motion.target = 1;
        }
    }
    onSlotLayoutChanged: {
        if (interacting)
            heldHeight = Math.max(heldHeight, slotLayout.totalHeight);
        retarget();
    }
    onItemsChanged: syncSlots()
    onEditModeChanged: {
        if (!editMode) {
            cancelInteraction();
            selectedIndex = -1;
        }
    }
    onWidthChanged: {
        if (width > 0 && !animateLayout)
            Qt.callLater(() => root.animateLayout = true);
    }
    Component.onCompleted: syncSlots()

    Spring {
        id: motion
        value: 1
        target: 1
        stiffness: Motion.spring("spatial", "default").stiffness
        dampingRatio: Motion.spring("spatial", "default").dampingRatio
    }

    ListModel { id: slots }

    // Where the dragged item will land.
    Loader {
        active: root.draggingIndex >= 0
        sourceComponent: Rectangle {
            readonly property var cell: root.slotLayout.slots[root.draggingIndex] ?? null
            x: cell ? cell.x : 0
            y: cell ? cell.y : 0
            width: cell ? cell.w : 0
            height: cell ? cell.h : 0
            radius: Math.min(root.slotRadius, height / 2)
            color: Qt.alpha(Colors.primary, ControlSpec.stateOpacity.dragged)
            Behavior on x { EffectsNumber { speed: "fast" } }
            Behavior on y { EffectsNumber { speed: "fast" } }
        }
    }

    Repeater {
        id: repeater
        model: slots
        delegate: GridSlot {}
    }

    component GridSlot: Item {
        id: slotItem

        required property int index
        required property string json
        readonly property var entry: JSON.parse(json)
        readonly property bool dragging: root.draggingIndex === index
        readonly property bool selected: root.editMode && root.selectedIndex === index
        property var from: null
        property var to: null
        property point dragPos: Qt.point(0, 0)
        readonly property real progress: root.motion.value

        function shown() {
            return { x: x, y: y, w: width, h: height };
        }
        function lerp(a, b) {
            return a + (b - a) * progress;
        }

        visible: to !== null
        x: dragging ? dragPos.x : (to ? lerp(from.x, to.x) : 0)
        y: dragging ? dragPos.y : (to ? lerp(from.y, to.y) : 0)
        width: to ? lerp(from.w, to.w) : 0
        height: to ? lerp(from.h, to.h) : 0
        z: dragging ? 2 : (selected ? 1 : 0)

        Loader {
            anchors.fill: parent
            sourceComponent: root.delegate
            onLoaded: {
                if ("modelData" in item)
                    item.modelData = Qt.binding(() => slotItem.entry);
                if ("index" in item)
                    item.index = Qt.binding(() => slotItem.index);
            }
        }

        Loader {
            anchors.fill: parent
            active: root.editMode
            sourceComponent: EditChrome {
                slot: slotItem
            }
        }
    }

    // Over a slot in edit mode: takes its clicks and drags; the selected one also gets its outline and handles.
    component EditChrome: Item {
        id: chrome

        required property GridSlot slot
        property var origin: null

        MouseArea {
            id: move
            anchors.fill: parent
            preventStealing: true
            cursorShape: chrome.slot.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => {
                const p = mapToItem(root, mouse.x, mouse.y);
                chrome.origin = { px: p.x, py: p.y, x: chrome.slot.x, y: chrome.slot.y };
            }
            onPositionChanged: mouse => {
                if (!chrome.origin)
                    return;
                const p = mapToItem(root, mouse.x, mouse.y);
                const dx = p.x - chrome.origin.px, dy = p.y - chrome.origin.py;
                if (!chrome.slot.dragging) {
                    if (Math.hypot(dx, dy) < Qt.styleHints.startDragDistance)
                        return;
                    chrome.slot.dragPos = Qt.point(chrome.origin.x, chrome.origin.y);
                    if (!root.beginDrag(chrome.slot.index))
                        return;
                }
                chrome.slot.dragPos = Qt.point(chrome.origin.x + dx, chrome.origin.y + dy);
                root.updateDragTarget(chrome.slot.dragPos.x, chrome.slot.dragPos.y);
            }
            onReleased: {
                chrome.origin = null;
                if (chrome.slot.dragging) {
                    // Land from where the pointer left it.
                    const at = chrome.slot.shown();
                    chrome.slot.from = at;
                    chrome.slot.to = at;
                    root.endDrag();
                } else {
                    root.selectedIndex = chrome.slot.index;
                }
            }
            onCanceled: {
                chrome.origin = null;
                if (chrome.slot.dragging) {
                    const at = chrome.slot.shown();
                    chrome.slot.from = at;
                    chrome.slot.to = at;
                }
                root.cancelInteraction();
                root.retarget();
            }
        }

        Loader {
            anchors.fill: parent
            active: chrome.slot.selected && !chrome.slot.dragging
            sourceComponent: Item {
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -border.width * 2
                    radius: Math.min(root.slotRadius, height / 2)
                    color: "transparent"
                    border.color: Colors.primary
                    border.width: Spacing.xs / 2
                }
                // Visual sides; in a mirrored grid the left side is the end of the row.
                ResizeHandle { slot: chrome.slot; side: "left"; edge: root.mirrored ? "end" : "start" }
                ResizeHandle { slot: chrome.slot; side: "right"; edge: root.mirrored ? "start" : "end" }
                ResizeHandle { slot: chrome.slot; side: "top"; edge: "top" }
                ResizeHandle { slot: chrome.slot; side: "bottom"; edge: "bottom" }
            }
        }
    }

    // A short bar centered on one side of the selected item, with a larger area to grab. Shown only on a side that
    // can move; dragging it moves that edge by whole cells.
    component ResizeHandle: MouseArea {
        id: handle

        required property GridSlot slot
        required property string side       // left | right | top | bottom, as seen
        required property string edge       // start | end | top | bottom, in the grid's terms
        readonly property bool across: side === "left" || side === "right"
        property var origin: null

        visible: root.resizingIndex === slot.index || root.canResize(slot.index, edge)
        width: across ? Spacing.xl : Math.max(Spacing.xl, slot.width - 2 * Spacing.lg)
        height: across ? Math.max(Spacing.xl, slot.height - 2 * Spacing.lg) : Spacing.xl
        x: side === "left" ? -width / 2 : (side === "right" ? slot.width - width / 2 : (slot.width - width) / 2)
        y: side === "top" ? -height / 2 : (side === "bottom" ? slot.height - height / 2 : (slot.height - height) / 2)
        preventStealing: true
        cursorShape: across ? Qt.SizeHorCursor : Qt.SizeVerCursor
        onPressed: mouse => {
            const p = mapToItem(root, mouse.x, mouse.y);
            origin = { px: p.x, py: p.y };
        }
        onPositionChanged: mouse => {
            if (!origin)
                return;
            const p = mapToItem(root, mouse.x, mouse.y);
            // How far the edge moved outward, in pixels: right and down are outward for the right and bottom sides.
            const out = side === "left" ? origin.px - p.x : side === "right" ? p.x - origin.px
                      : side === "top" ? origin.py - p.y : p.y - origin.py;
            const pitch = across ? root.slotLayout.colW + root.gap : root.rowHeight + root.gap;
            root.previewResize(slot.index, edge, out / pitch);
        }
        onReleased: {
            origin = null;
            root.commitResize();
        }
        onCanceled: {
            origin = null;
            root.cancelInteraction();
        }

        Rectangle {
            anchors.centerIn: parent
            width: handle.across ? Spacing.xs : Spacing.xl
            height: handle.across ? Spacing.xl : Spacing.xs
            radius: Spacing.xs / 2
            color: Colors.primary
        }
    }
}
