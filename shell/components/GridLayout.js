// Grid packing for EditableGrid: places items of w x h cells on a grid of `columns`, keeping saved positions
// where they fit and first-fitting the rest. Pure functions, no QML.
//
// Ported from DankMaterialShell's quickshell/Common/GridLayout.js (MIT, Copyright (c) 2025 Avenge Media LLC;
// now github.com/duxlabs-dev/dux-shell, commit e689cd2). Changed: no half-step rows, no right-to-left mirroring
// and no shrinking rows (Rutile does not use them yet), and fitNew takes the new item whole.
.pragma library

// Cells for `cards` (each {w, h} and optionally a saved {col, row}), placed in `order` (indices into cards):
// {cells: [{col, row, cols, rows} or null], rows}. `isAvailable(id)` false leaves an item out.
function packCells(cards, order, columns, isAvailable, gravity) {
    const cells = [];
    const taken = [];
    let rows = 0;

    for (let p = 0; p < order.length; p++) {
        const sourceIndex = order[p];
        const card = cards[sourceIndex];
        if (!card)
            continue;
        if (isAvailable && !isAvailable(card.id)) {
            cells[sourceIndex] = null;
            continue;
        }
        const w = Math.max(1, Math.min(columns, Math.round(card.w || 1)));
        const h = Math.max(1, Math.round(card.h || 1));
        const cell = positioned(card)
            ? settle(taken, Math.max(0, Math.min(columns - w, Math.round(card.col))), Math.max(0, Math.round(card.row)), w, h)
            : firstFit(taken, columns, w, h);
        taken.push(cell);
        cells[sourceIndex] = cell;
    }

    if (gravity)
        compact(taken);
    for (let i = 0; i < cells.length; i++) {
        const cell = cells[i];
        if (!cell)
            continue;
        rows = Math.max(rows, cell.y + cell.h);
        cells[i] = { "col": cell.x, "row": cell.y, "cols": cell.w, "rows": cell.h };
    }
    return { "cells": cells, "rows": rows };
}

// Saved positions only settle downward, so a shrink or removal above leaves a hole; gravity pulls everything up into it.
function compact(taken) {
    const ordered = taken.slice().sort((a, b) => a.y - b.y || a.x - b.x);
    for (const cell of ordered) {
        const others = taken.filter(other => other !== cell);
        while (cell.y > 0 && !overlaps(others, cell.x, cell.y - 1, cell.w, cell.h))
            cell.y--;
    }
}

function positioned(card) {
    return Number.isFinite(card.col) && Number.isFinite(card.row);
}

function overlaps(taken, x, y, w, h) {
    return taken.some(cell => x < cell.x + cell.w && cell.x < x + w && y < cell.y + cell.h && cell.y < y + h);
}

function settle(taken, x, y, w, h) {
    while (overlaps(taken, x, y, w, h))
        y++;
    return { "x": x, "y": y, "w": w, "h": h };
}

function firstFit(taken, columns, w, h) {
    const ceiling = taken.reduce((top, cell) => Math.max(top, cell.y + cell.h), 0);
    for (let y = 0; y < ceiling; y++) {
        for (let x = 0; x + w <= columns; x++) {
            if (!overlaps(taken, x, y, w, h))
                return { "x": x, "y": y, "w": w, "h": h };
        }
    }
    return { "x": 0, "y": ceiling, "w": w, "h": h };
}

// Cells plus pixel rects ({x, y, w, h} merged into each slot) for a grid `width` wide.
function packCards(cards, order, columns, width, gap, rowHeight, isAvailable, gravity) {
    const packed = packCells(cards, order, columns, isAvailable, gravity);
    const layout = {
        "slots": [],
        "rows": packed.rows,
        "totalHeight": packed.rows > 0 ? packed.rows * rowHeight + (packed.rows - 1) * gap : 0,
        "columns": columns,
        "width": width,
        "colW": (width - gap * (columns - 1)) / columns,
        "rowHeight": rowHeight,
        "gap": gap
    };
    layout.slots = packed.cells.map(cell => cell ? Object.assign(slotRect(layout, cell.col, cell.row, cell.cols, cell.rows), cell) : null);
    return layout;
}

function sameRect(a, b) {
    return a.x === b.x && a.y === b.y && a.w === b.w && a.h === b.h;
}

function slotRect(layout, col, row, cols, rows) {
    return {
        "x": col * (layout.colW + layout.gap),
        "y": row * (layout.rowHeight + layout.gap),
        "w": cols * layout.colW + (cols - 1) * layout.gap,
        "h": rows * layout.rowHeight + (rows - 1) * layout.gap
    };
}

// The cell nearest to a top-left corner at (x, y) for an item of cols x rows, kept inside the columns.
function cellAt(layout, x, y, cols, rows) {
    const col = Math.round(x / (layout.colW + layout.gap));
    return {
        "col": Math.max(0, Math.min(layout.columns - cols, col)),
        "row": Math.max(0, Math.round(y / (layout.rowHeight + layout.gap)))
    };
}

// With gravity, a tile dropped onto the stack it came from rises back toward the hole it left. So the drop tries
// the target row and the rows below it, packing each, and keeps the one that settles nearest the target.
function dropInto(items, cells, index, target, pack) {
    const origin = cells[index];
    if (!origin || !target || !pack)
        return items;
    if (target.col < origin.col + origin.cols && origin.col < target.col + origin.cols && target.row < origin.row + origin.rows && origin.row < target.row + origin.rows)
        return items;
    const limit = cells.reduce((bottom, cell) => cell ? Math.max(bottom, cell.row + cell.rows) : bottom, 0) + origin.rows;
    let best = null;
    for (let row = target.row; row <= limit; row++) {
        const trial = items.map((item, i) => i === index ? Object.assign({}, item, { "row": row }) : item);
        const landed = pack(trial)[index]?.row;
        if (landed === undefined)
            return items;
        const distance = Math.abs(landed - target.row);
        if (!best || distance < best.distance || (distance === best.distance && landed >= target.row))
            best = { "trial": trial, "distance": distance };
        if (landed >= target.row)
            break;
    }
    return best.trial;
}

// The items with the col and row they were packed at, so a commit saves where everything is.
function placedItems(items, slots) {
    return items.map((item, i) => slots[i] ? Object.assign({}, item, { "col": slots[i].col, "row": slots[i].row }) : item);
}

// The row limit for a change: `maxRows` (0 for none), or the rows already used if they exceed it, so a layout
// that is already too tall can still change without first having to shrink.
function rowLimit(cards, order, columns, maxRows) {
    if (!(maxRows > 0))
        return Infinity;
    return Math.max(maxRows, packCells(cards, order, columns, null, false).rows);
}

function fitWithin(cards, order, columns, limit, index, want, min) {
    let best = null;
    for (let w = Math.min(columns, want.w); w >= min.w; w--) {
        for (let h = want.h; h >= min.h; h--) {
            const trial = cards.slice();
            trial[index] = Object.assign({}, cards[index], { "w": w, "h": h });
            if (packCells(trial, order, columns, null, false).rows > limit)
                continue;
            const distance = want.w - w + want.h - h;
            const better = !best || distance < best.distance || (distance === best.distance && w * h > best.w * best.h);
            if (better)
                best = { "w": w, "h": h, "distance": distance };
            break;
        }
    }
    return best ? { "w": best.w, "h": best.h } : null;
}

// The size nearest `want` (down to `min`) that item `index` can take without the grid outgrowing maxRows; null if
// none fits.
function fitResize(cards, columns, maxRows, index, want, min) {
    const order = cards.map((card, i) => i);
    return fitWithin(cards, order, columns, rowLimit(cards, order, columns, maxRows), index, want, min);
}

// The same for a new item appended to the grid: the size it can have, or null when there is no room.
function fitNew(cards, columns, maxRows, item, min) {
    const order = cards.map((card, i) => i);
    const limit = rowLimit(cards, order, columns, maxRows);
    const want = { "w": item.w || 1, "h": item.h || 1 };
    return fitWithin(cards.concat([Object.assign({}, item, want)]), order.concat([cards.length]), columns, limit, cards.length, want, min);
}
