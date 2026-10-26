# Components (`shell/components/`) and the gallery

Import with `import qs.common` and `import qs.components`. Quickshell resolves `qs` to the
directory containing the entry file, so run things from `shell/`.

| Component | What it is |
|---|---|
| `Surface` | rounded tonal surface; set `tone` (not `color`) so changes animate |
| `StateLayer` | hover, focus, pressed, dragged overlay plus the MouseArea; `clicked()` |
| `Icon` | Material Symbols ligature: `name`, `size`, `fill`, `weight` |
| `Button` | types `filled` `tonal` `elevated` `outlined` `text`; sizes `xs` `s` `m` `l` `xl`; `shape` round or square; `toggle`/`checked`; `iconName` |
| `IconButton` | types `standard` `filled` `tonal` `outlined`; same sizes; `widthVariant` default (square), narrow, wide; `toggle`/`checked` |
| `ButtonBase` | shared behavior (not used directly) |
| `Switch` | `checked`, `toggled(bool)`, `controlled`; optional `checkedIcon` / `uncheckedIcon` in the handle |
| `Slider` | horizontal; `from`, `to`, `value`, `stepSize` (0 = continuous), `moved(real)` when the user changes it; `size` `xs` (default) `s` `m` `l` `xl`; `startIcon`, `endIcon` track icons on `m` and up |
| `ProgressBar` | linear, determinate; `value` 0..1, `wavy`, `animated` |
| `Tile` | Quick Settings tile (Android 16 SystemUI): `text`, `secondaryText`, `iconName`, `active`, `available`, `dualTarget`, `iconOnly`, `controlled`; `clicked()`, `toggled(bool)` |
| `Chip` | `assist` (flat or `elevated`) or `filter` (`selected`, `controlled`, check when selected); `iconName`, `trailingIconName` |
| `ListItem` | `text`, `supportingText`, `iconName`, `trailingText`, a trailing slot for a control, `selected`, `position` in a segmented group |
| `EditableGrid` | `items` ({id, w, h, col, row, minW, maxW, minH, maxH}), `columns`, `rowHeight`, `gap`, `maxRows`, `gravity`, `delegate` (gets `modelData`, `index`), `editMode`, `selectedIndex`, `commitHandler(items)`, `canResize(index, edge)`, `fitNew(item)` |

```qml
Button { text: "Create a widget"; iconName: "auto_awesome"; type: "filled"; size: "m"; onClicked: ... }
IconButton { iconName: "wifi"; type: "tonal"; toggle: true; onToggled: c => ... }
```

Sizes, shapes, color roles and state opacities come from `tokens/components.json`, generated from the
vendored Compose Material3 token sources into `ControlSpec.qml`. Behavior implemented:

- pressed shape morph: the corner radius chases the pressed shape with a spatial spring
- toggle: selected shape and colors swap (round buttons become squarer when selected)
- container and color changes animate with effects springs (`Behavior on color { EffectsColor {} }`), including
  theme switches
- disabled: container 10%, content 38% opacity; keyboard activation with Space/Return; focus state layer

Switch, Slider and ProgressBar take every value from `ControlSpec.switchSpec`, `sliderSpec` and
`progressSpec`, generated from the Compose token files. Values Compose hardcodes rather than tokenizes are
parsed from its sources and land under `impl` (the slider's 2 px inner corner, the 240 px default bar width,
the wave thresholds and the progress spring); the generator fails if those sources change. Behavior:

- Switch: the handle snaps to 28 px while pressed and springs (fast spatial) to 16 or 24 px on release;
  hover and press lighten the handle; disabled colors are composited over the surface, as Compose does.
  Its state layer is a 40 px circle around the handle. Its colors (primary when on, on-surface when off) come
  from the M3 spec, not a token, because the token file only gives the size.
- Slider: click or drag anywhere; arrows move a step (or 1/100), PageUp/PageDown a tenth, Home/End the ends.
  Tick dots sit where stepped values put the handle; Compose spaces them slightly differently.
  Sizes (D36): `xs` is Compose's default slider (16 px track); `s` 24, `m` 40 (Quick Settings), `l` 56 and
  `xl` 96 px tracks, with taller handles and larger outer corners, from Material Components Android's tokens
  (`impl.sizes`). On the larger sizes a part of the track shorter than its corners shrinks its corners instead
  of disappearing, except on stepped sliders. `startIcon` sits at the start of the active part and `endIcon`
  at the end of the inactive part, each only while its part has room for the icon plus 10 px on both sides;
  the end icon replaces the stop dot. Icons are created only when set. Under `LayoutMirroring` the track fills
  from the right and the left arrow key increases.
- ProgressBar: the wave fades in over `Motion.long2` with the standard easing and out with emphasized
  accelerate; it only animates while visible.

Switch, Tile and filter Chip toggle themselves by default, which suits the gallery. Anything wired to the
system sets `controlled: true` and binds the state (`active: Network.wifiEnabled`): a click then only emits
`toggled(wanted)`, the owner applies the setting, and the control changes when the bound state does. A change
that fails never shows, and one made elsewhere does (D33).

Tile, Chip and ListItem (`ControlSpec.tileSpec`, `chipSpec`, `listSpec`):

- Tile follows Android 16's Quick Settings tile from SystemUI (`Tile.kt`, `CommonTile.kt`, vendored and
  parsed like the Compose files). The Googlebook screenshots show the same tile (D32,
  `docs/reference/README.md`). Inactive tiles are
  pills, active ones 24 px corners; on a dual-target tile the icon toggles and the body emits `clicked()`
  (open details). The focus border SystemUI draws is not done yet.
- Chip spacing is Compose's `ChipArrangement`: 8 px padding at the ends, 8 px between elements, 4 px between a
  filter chip's icon and label. Elevated chips have no shadow yet (as elevated buttons).
- ListItem uses the expressive shapes: 4 px at rest, 12 hovered, 16 pressed, focused or selected, sprung. In
  a segmented group the first item keeps 16 px top corners and the last 16 px bottom corners
  (`ListItemDefaults.segmentedShapes`); put items 2 px apart (`listSpec.segmentedGap`) on a container.

EditableGrid (plan 1.6) is the grid under Quick Settings tiles and, later, desktop widgets (D17). Its behavior
(layout without gaps, select, drag, resize with shrinking neighbors, row limit, right to left, commits through
the owner) is described with examples in `docs/editable-grid.md`.

Tile works at any size: content stays vertically centered, and under `LayoutMirroring` the icon sits on the
right. The other components do not mirror yet.

## One correction to the tokens

`ButtonXSmallTokens.kt` is not yet corrected upstream: Compose overrides it in `Button.kt` with 12 px
padding and a 4 px icon gap (the token file says 16 and 8). `tools/gen_components.py` applies the
override, records it in `components.json`, and fails if the upstream TODOs disappear so it gets reviewed.

## Not done yet

- **Slider:** vertical and range sliders, the value label above the handle, centered sliders, icons in the
  other two track slots (end of the active part, start of the inactive part) that MDC also offers.
- **Progress:** indeterminate (flat and wavy) and circular indicators. The tokens for circular are generated.

- **Ripple:** state layers only. Rounded clipping of a ripple needs masking; decide from the gallery.
- **Elevation shadows:** `elevated` shows its container color only, so it is faint on dark surfaces.
- **Focus ring:** keyboard focus shows the state layer, not the M3E focus ring.
- **Exact font weights** (500) and filled icons need `font.variableAxes`; see `docs/fonts.md`.

## The gallery

```
quickshell -p shell/gallery.qml        # a window with every role, shape, type style, button and a motion demo
python3 tools/qtws.py render --out render --mode dark    # or light: offscreen PNG slices to look at
```

The gallery window's toggle (top right) switches light and dark live, and click a motion lane to see
each spring. `render` uses the real fonts when `RUTILE_FONT_DIRS` finds them (the dev shell sets it).
Changing a token or component and re-rendering is the quickest way to check a look without a session.

## What is verified where

Offscreen: sizes, colors per type, toggle, disabled, press morph, keyboard, state layer, springs,
pixels through a software renderer, gallery contents, render tool, `make check` (lint, 120+ tests).

Run on Qt 6.12, the Qt the flake's Quickshell is built on. Qt 6.7 is the minimum (D31): the components use
per-corner radii and `font.variableAxes`.

Seen working in a real Quickshell session: the gallery configuration loads without errors, which
exercises `import qs.*` resolution, singleton registration, `FloatingWindow` and `PaletteWatcher`.
Still unconfirmed visually in a real session: the look itself (compare your window to `render`).
