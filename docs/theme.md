# Theme pipeline

```
seed color + scheme + mode + contrast
        |  tools/palette.py render
        v
matugen (theme/matugen.toml + theme/templates/palette.json)
        v
validated, atomically written palette.json   <- the only color input QML sees
        v
Colors singleton (Phase 1.3)
```

`palette.json` (format 1) holds both `dark` and `light` role tables, so a mode
switch needs no re-render. The producer can change without touching QML.

Usage:

    python3 tools/palette.py render --seed '#134aae' --out ~/.cache/rutile/palette.json
    python3 tools/palette.py render --image ~/Pictures/wallpaper.jpg --out ~/.cache/rutile/palette.json
    python3 tools/palette.py validate ~/.cache/rutile/palette.json

`--image` seeds the palette with the image's most dominant color (matugen's `image` source with
`--source-color-index 0`, so it never asks). `render` refuses bad input, validates matugen's output against `theme/roles.json`
(49 roles, `#rrggbb`) and replaces the target atomically (mode 0644). If anything
fails the previous palette is left in place.

## Measured: matugen 4.2.0 implements the 2021-era color spec

Cross-checked against `materialyoucolor` 3.0.4 (independent Python port of
Material Color Utilities, supports both spec versions), all 9 scheme types, two
seeds, both modes, contrast 0:

| Reference spec | Agreement |
|---|---|
| 2021 | 94.7% (94 of 1764 values differ) |
| 2025 | about 60% (2140 of 5292 differ across a wider test matrix) |

- The 2021 differences are confined to 9 roles (`on_*_container`,
  `on_surface_variant`, `outline`, `outline_variant`, `surface_variant`,
  `secondary_container`), listed in `KNOWN_2021_DIVERGENCE` in
  `tests/test_palette.py`. Example: seed `#134aae`, tonal spot, light mode,
  `on_primary_container`: matugen `#001848`, reference `#304578`.
- The 2025 spec (used by current M3 Expressive) adds roles such as `primary_dim`
  and changes tonal-spot values. Example: dark `primary` for seed `#134aae` is
  `#b2c5ff` in matugen and `#b9c6ee` in the 2025 reference. matugen master (as
  checked) has no 2025 support and no `*_dim` roles.
- `test_documents_that_matugen_is_not_2025_spec` fails when matugen gains 2025
  support, as a prompt to revisit this decision.

Open decision: whether v1 accepts the 2021 palette (simplest, matugen also
themes other apps) or adds a 2025-spec producer behind the same `palette.json`.

## Optional test dependencies

Tests needing matugen (`RUTILE_MATUGEN` or PATH) or `materialyoucolor` skip with
an explicit message when absent. matugen is invoked as an external program and
is not vendored.
