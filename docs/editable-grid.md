# EditableGrid: how it behaves

The grid under the Quick Settings tiles and, later, the desktop widgets (D17). This page is the reference for its
behavior: what the user sees, the rules behind it, and where each rule lives in the code. If you change a rule,
change this page and the test named next to it in the same commit.

- Code: `shell/components/EditableGrid.qml` (state, input, motion) and `shell/components/GridLayout.js` (pure
  layout functions; packing ported from DankMaterialShell, MIT, see `NOTICE`).
- Tests: `tests/qml/tst_editable_grid.qml`, plus `tests/qml/tst_gallery.qml` for the gallery demo and
  `tests/qml/tst_qs_controls.qml` for the Tile's own layout.
- Decisions: D17 (one shared grid), D31 (memory), D33 (controlled state), D34 (resizing), D35 (no gaps).
- Try it: `quickshell -p shell/gallery.qml`, section "Editable grid (Quick Settings tiles)", "Edit tiles".

Diagrams below use a 4-column grid; `[A ]` is tile A one cell wide, `[B     ]` two cells, `.` a free cell.

## Data

An item is plain saved data:

| Field | Meaning |
|---|---|
| `id` | identity; delegates and the selection follow it across changes (duplicates are allowed, matched in order) |
| `w`, `h` | size in cells (default 1); clamped to the limits below |
| `col`, `row` | the cell it was placed at; written by every commit, optional on input |
| `minW`, `maxW`, `minH`, `maxH` | optional limits |

Limits: width defaults to 1..`columns`, height to 1..`maxRows` (unbounded when `maxRows` is 0). So every item can
grow to the full width and in height unless it says otherwise; set min equal to max to fix a size.

The grid never changes `items` itself when it has a `commitHandler`: it calls `commitHandler(items)` with every
item's new `col`, `row`, `w` and `h`, and the owner saves them and sets `items` (the same rule as toggles, D33:
show what was applied). If the owner does not apply a change, the grid springs back to what `items` says. With no
handler the grid assigns `items` itself, which suits demos only. It is a callback, not a signal, because Qt 6.12
hands array signal arguments over as sequences that fail `Array.isArray`.

## Layout: where items go

`packCells` places items one by one. An item with a saved `col`/`row` goes there, or straight down until it no
longer overlaps anything already placed. An item without one goes to the first free cell (`gravity` off) or below
everything, in list order (`gravity` on, so the flow below puts it after the items before it).

With `gravity` on (Quick Settings, the default), `compact()` then removes every gap (D35):

1. Items are taken in reading order: by row, then by column.
2. Each takes the first free cell at or after the end of the item before it, moving to the start of the next row
   when it does not fit in what is left of the row.
3. Nothing grows. Free space is left only at the end of a row, when the next item does not fit there; the last
   item never stretches into it.

```
saved:      [A ] .  [B ] .        after:   [A ][B ][C ][D ]
            [C ][D ] .   .
B slides into the gap; C and D move up into the free end of the row above.

saved:      [A        ] .         after:   [A        ] .        B does not fit after A, so it starts
            [B     ][C ] .                 [B     ][C ] .       the next row; C stays behind B, it does
                                                                not jump ahead into the free cell.
```

The order is the point: an earlier version only pulled items up, which let a later small item jump ahead into a
hole. Tests: `test_gravity_leaves_no_gaps_and_stretches_nothing`, `test_saved_positions_and_gravity`.

With `gravity` off (meant for the desktop widget grid), items stay where they were put and holes are allowed.

Pixel geometry: column width is `(width - gap * (columns - 1)) / columns`; a cell is that wide and `rowHeight`
tall, with `gap` between cells; an item spanning cells includes the gaps inside it. Under `LayoutMirroring`
(right-to-left, see below) column 0 is on the right.

## Edit mode

Outside `editMode` the grid is a plain layout and delegates get all input. In edit mode an overlay on each item
takes the pointer, so the delegate (a Tile) does not toggle; it is created only while editing.

### Select

A click (press and release without moving past the platform's drag distance, `Qt.styleHints.startDragDistance`)
selects the item: it gets a primary outline and its resize handles. `selectedIndex` follows the item's `id` when
items change, and is cleared when edit mode ends. A "Remove" action belongs to the owner: remove
`items[selectedIndex]` and set `items`.

### Move (drag)

Pressing an item and moving past the drag distance starts a drag (it also selects the item).

- The item follows the pointer; a translucent placeholder shows the cell it would land in.
- The target cell is the one nearest the item's top-left corner, kept inside the columns and no lower than the
  row limit allows (`maxRows`, or one row past the current bottom when there is no limit).
- Everything else re-flows live around the target, from where it was when the drag began (so items do not drift
  while the pointer moves back and forth).
- With gravity, dropping means "put it at this place in the order". `dropInto` tries the target row and the
  rows below it and keeps the one where the item actually settles nearest the target, so dropping an item where
  another one is takes that one's place and pushes it along. Dropping it into free space at the end of a row puts
  it after that row's last item, since no gap may stay.
- The grid keeps its height during the drag, so it does not shrink under the pointer; it settles on release.
- Release commits only if something moved. A drag that ends where it started commits nothing.

```
before:   [A     ][B ][C ]        drag D onto C:   [A     ][B ][D ]
          [D ] .   .   .                           [C ] .   .   .
```

Tests: `test_drag_moves_an_item_and_the_rest_make_room`, `test_drag_shows_a_placeholder_and_holds_the_height`,
`test_the_height_holds_while_dragging`, `test_a_refused_commit_springs_back`.

### Resize (handles)

The selected item shows a handle on each side that can move: left, right, top, bottom. A handle is a short
primary bar centered on that side, with a larger area to grab. Dragging it moves that edge by whole cells; the
pointer distance is divided by the cell pitch and rounded.

A side can move when its edge can go outward (there is room, or the neighbors can make room within the row limit)
or inward (the item is above its minimum along that axis). `canResize(index, edge)` answers this by trying the
change, so a handle is never shown where nothing would happen:

```
maxRows 1:
[A ][B ][C     ]   C has minW 2: A, B and C show no handles at all (nobody can shrink, no row to move to)
[A ][B ][C ] .     B shows left and right handles: its neighbors can move along the row
```

What a resize does to the neighbors (D34):

1. The item takes its new rectangle.
2. A neighbor it now overlaps is cut back from the side facing it, down to that neighbor's minimum. Of the cuts
   that remove the overlap, the one keeping the most cells wins; on a tie, the cut along the resize (across the
   columns for left and right handles, down the rows for top and bottom).
3. A neighbor that would have to go below its minimum keeps its size and is moved away instead (packed further
   on, then the gravity flow places it).
4. With gravity, everything then flows (rules above). So shrinking an item lets the items after it slide forward;
   nothing grows back into the space.

```
grow A's right edge by 1:
[A     ][B     ]   ->   [A        ][B ]          B gives up a column (minW 1)
grow it again:
[A        ][B ]    ->   [A           ]           B is at its minimum, so it moves to the next row
                        [B ] .   .   .
shrink A back by 2:
[A           ]     ->   [A     ][B ] .           B slides forward; it stays 1 wide (nothing grows back)
[B ] .   .   .
```

Row limit: if the result would need more rows than `maxRows` (or than the grid already uses, if that is more), the
grid takes the largest move toward the pointer that does fit, and none if no move fits. Shrinks are kept when the
change is committed: a neighbor that gave up cells stays smaller.

A start-edge (left in left-to-right) shrink with gravity on ends up like an end-edge shrink, because the item then
slides forward to close the gap it left.

The resize commits on release if anything changed.

Tests: `test_growing_into_a_neighbor_shrinks_it_then_moves_it`,
`test_a_neighbor_is_cut_along_the_resize_and_items_stay_inside`, `test_handles_show_only_on_sides_that_can_move`,
`test_every_edge_moves`, `test_max_rows_limits_resizes_and_new_items`.

### Adding

`fitNew(item)` returns the size a new item could have when appended (its wanted size, or smaller down to its
minimum) without the grid outgrowing `maxRows`, or null when there is no room. With gravity it is checked with
the same flow, so a new item counts as going after the last one, not into a free cell earlier in the grid.
Dragging items in from outside (the Add sheet) is not built yet.

## Right to left

The grid reads `LayoutMirroring.enabled`, which the shell sets once at its root (with `childrenInherit`) for a
right-to-left locale. Then column 0 is on the right, dragging toward the left moves toward the end of the row, and
the left handle moves the end edge. Rows still go top to bottom. The Tile lays out with anchors, so under the same
mirroring its icon sits on the right and its labels to the left of it. Only the Tile and the grid mirror so far.
Tests: `test_right_to_left_mirrors_columns_drags_and_handles`, `test_tile_mirrors_for_right_to_left`.

## Sizes of tiles in the Quick Settings grid

The delegate decides how an item looks at a size. The gallery's Quick Settings demo shows a 1-wide item as an
icon-only Tile and anything wider as icon plus labels. A taller Tile keeps its content vertically centered. A real
panel will save only `id` and size and look the rest up by `id`; the gallery puts labels in the items for brevity.

## Motion and memory

- Every layout change moves items on one shared spring (`Motion.spring("spatial", "default")`): each item lerps
  from where it was shown to its new cell, so a change made mid-motion starts from where things are on screen. The
  first layout does not animate.
- Delegates are kept across reorders and resizes (a ListModel keyed by `id`); only new items are created.
- The edit overlay exists only in edit mode, and the outline and handles only on the selected item.
- Measured (`tools/dev/memcost.py`, `docs/memory.md`): a 9-tile grid costs about 25 KiB per slot on top of the
  tiles; edit mode adds about 11 KiB per slot while editing.

## Not done

- Keyboard: selecting, moving and resizing without a pointer.
- Dragging items in from outside the grid (the Add sheet) and out of it.
- The desktop widget grid's own rules (plan 4.4); it is expected to run with `gravity` off.
