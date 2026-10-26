# Memory: keeping the shell light

The shell runs all day, so memory is a design constraint (D31), not a cleanup for later. Qt itself costs
about 55 to 100 MB before any of our QML loads; what we control is how much each visible thing adds and how
much is created before anyone looks at it.

## Rules

1. **Create on demand.** Anything not on screen at startup is behind a `Loader` (or Quickshell's
   `LazyLoader`) with `active` bound to whether it is needed: popups, Quick Settings, the launcher, menus,
   dialogs, settings pages, every widget not on the visible desktop. Unload what has been closed for a while
   rather than hiding it. Inside components, optional parts load only when used (`Button` creates its icon
   only when it has one, `Switch` its handle icon, `ProgressBar` its wave).
2. **Animate on the property, not with helper objects.** Colors and opacities use
   `Behavior on color { EffectsColor {} }` / `Behavior on opacity { EffectsNumber {} }`: Qt's C++ animations
   on the M3 effects-spring curve. A separate animated-color object cost three times as much. `Spring` (a
   JavaScript spring) is for spatial motion that must overshoot, and only where the motion is visible.
3. **No Canvas for what Rectangles can draw.** A Canvas keeps a pixel buffer and repaints in JavaScript.
   Rectangles (with per-corner radii) draw tracks, bars, dots and pills. A Canvas is only for real paths
   (the progress wave), and only created while it draws.
4. **Images set `sourceSize`** so they decode at the size shown, not the file's size.
5. **Nothing runs when idle.** Animations and frame callbacks run only while something moves
   (`Spring` stops when settled; the wave stops when hidden). No polling timers where a signal exists.
6. **Share, don't copy.** Tokens, palettes and specs live in singletons; components read them. Repeaters and
   ListViews over models instead of hand-made copies; ListView for anything long, so delegates are recycled.

`tools/lint_hardcoded.py` (part of `make check`) fails on an eager Canvas, an Image without `sourceSize` and a
FrameAnimation hard-wired to run. The rest is review: when adding a component, measure it.

## Measuring

```
python3 tools/dev/memcost.py Button Switch --count 300      # KiB added per instance, median of 3 runs
MEMCOST_BACKEND=software python3 tools/dev/memcost.py Slider  # the software renderer instead
```

It loads N and then 2N copies offscreen and divides the difference, so one-time costs (fonts, caches, type
compilation) are not charged to each copy. It uses Qt's GPU scene graph (Mesa's rasterizer without a GPU),
like a session. The software renderer caches every rounded rectangle as an image, so its numbers inflate
anything rounded; do not tune for it. Results are stable to a fraction of a KiB between runs.

## Where the memory goes (October 2026, Qt 6.12, per instance)

| | before | after | what changed |
|---|---|---|---|
| Surface | 17.4 KiB | 6.3 KiB | color animation on the property instead of a `SpringColor` object |
| StateLayer | 19.0 | 13.7 | opacity as a Behavior instead of a JavaScript spring |
| Icon | 8.2 | 5.9 | variable axes as one binding instead of a function and five handlers |
| Button | 83.6 | 61.6 | the above, and the icon only when there is one |
| IconButton | 70.1 | 54.1 | the above |
| Switch | 125.2 | 90.3 | three color Behaviors, handle icon on demand |
| Slider | 140.3 | 71.6 | Rectangles instead of a Canvas |
| Slider with sizes and track icons | 71.6 | 79.9 | sizes, icons and right to left; one Loader for both icons (about 4), the rest bindings; `m` with an end icon is 118.9 |
| ProgressBar | 92.0 | 50.0 | Rectangles; the wave's Canvas only while it shows |
| Chip | | 71.1 | icons only when shown |
| ListItem | | 85.1 | includes its shape spring |
| Tile | | 101.6 | one icon for both layouts; a dual-target tile adds a state layer (about 160) |
| ShapeMorph | | 47 to 418 | QtQuick.Shapes' curve renderer; grows with the curve count: circle 47, cookie9Sided 115, softBoom (192 curves) 418. Idle state is the name only (D37) |
| StatusPill | 122.8 | 58.3 | always on screen (one per screen): one `Icon` with three ligatures instead of three (93.2), then no container while closed and 16 px icons |
| QuickSettingsPanel, open | | 1421 | 5 tiles, 2 sliders, the grid, 4 icon buttons; exists only while open (LazyLoader) |
| EditableGrid, 9 tiles | | 1256 | 9 tiles (114 each in that measurement) plus about 25 per slot; edit mode adds about 11 per slot (handles only on the selected item), only while editing |

For scale: an empty `Item` is about 3 KiB, a `Rectangle` 2, a `Text` 6, a `MouseArea` 2, a `Behavior` with
its animation 2, a `Spring` about 7 and a JavaScript binding about 0.3 (0.7 for a color expression).
