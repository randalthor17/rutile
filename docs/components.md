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

```qml
Button { text: "Create a widget"; iconName: "auto_awesome"; type: "filled"; size: "m"; onClicked: ... }
IconButton { iconName: "wifi"; type: "tonal"; toggle: true; onToggled: c => ... }
```

Sizes, shapes, color roles and state opacities come from `tokens/components.json`, generated from the
vendored Compose Material3 token sources into `ControlSpec.qml`. Behavior implemented:

- pressed shape morph: the corner radius chases the pressed shape with a spatial spring
- toggle: selected shape and colors swap (round buttons become squarer when selected)
- container and color changes animate with effects springs (`SpringColor`), including theme switches
- disabled: container 10%, content 38% opacity; keyboard activation with Space/Return; focus state layer

## One correction to the tokens

`ButtonXSmallTokens.kt` is not yet corrected upstream: Compose overrides it in `Button.kt` with 12 px
padding and a 4 px icon gap (the token file says 16 and 8). `tools/gen_components.py` applies the
override, records it in `components.json`, and fails if the upstream TODOs disappear so it gets reviewed.

## Not done yet

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

Offscreen with Qt 6.4: sizes, colors per type, toggle, disabled, press morph, keyboard, state layer,
springs, pixels through a software renderer, gallery contents, `make check` (lint, 100+ tests).
Not verifiable without Quickshell: `import qs.*` resolution and singleton registration (we generate a
qmldir for tests; Quickshell is expected to do the equivalent), `FloatingWindow`, `PaletteWatcher`.
