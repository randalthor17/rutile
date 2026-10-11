# Fonts

| Role | Font | Source | License |
|---|---|---|---|
| Text | Google Sans Flex 4.007 (variable) | `nix/googlesans-flex.nix` (our package; not in nixpkgs) | OFL-1.1 |
| Icons | Material Symbols Rounded (variable) | `pkgs.material-symbols` | Apache-2.0 |

Both M3 font roles (`plain` and `brand`) use Google Sans Flex. Fonts are not
vendored in this repository; they come from the nix packages.

## One source of truth

`theme/fonts.json` records each font's family name, file name, package, license
and variation axes. `make generate` turns it into `Fonts.qml` and the `Type`
family defaults. When the real font files are available, tests check that the
file reports exactly that family name and those axes, so the config cannot drift.

Axes, as measured from the files:

- Google Sans Flex: `opsz` 6-144 (default 18), `wdth` 25-151, `wght` 1-1000,
  `GRAD` 0-100, `ROND` 0-100, `slnt` -10-0
- Material Symbols Rounded: `FILL` 0-1, `GRAD` -50-200, `opsz` 20-48, `wght` 100-700

## Using them in QML

```qml
Text {
    text: "Settings"
    font: Type.font(Type.titleMediumEmphasized)   // family, size, weight, letter spacing
    lineHeight: Type.titleMediumEmphasized.lineHeight
    lineHeightMode: Text.FixedHeight
}

Text {                                            // icons are ligatures: the name is the glyph
    text: "settings"
    font.family: Fonts.iconFamily
    font.pixelSize: 24
}
```

## Making Qt see the fonts

In production the NixOS module installs them system-wide (Phase 6). In
`nix develop`, the shell sets `RUTILE_FONT_DIRS` to the packages' font
directories and `FONTCONFIG_FILE` to a file written by `tools/fontconf.py`.
That file includes the system fontconfig first and then adds the directories, so
no other font is lost. Outside nix, set `RUTILE_FONT_DIRS` yourself, or install
the fonts normally.

## What is and is not verified

Verified with the real font files, offscreen:

- both fonts load into Qt and report the configured family names; `Type.font()` carries the right
  family, size and weight; the `settings` icon ligature renders as one glyph; fontconfig resolves the
  family through the generated config
- **On Qt 6.11 and 6.12** (`font.variableAxes` exists): `Type.font()` returns a font whose `wght` and
  `opsz` axes equal the style's weight and size; Emphasized styles render heavier (weights 500 and 700,
  not just the named Regular and Bold); `Icon.fill` changes the `FILL` axis (a filled `star` carries
  clearly more ink than the outline one). These run in `make check` when the fonts are available.
- On **Qt 6.4** (no `font.variableAxes`) those tests skip with their reason, and only the named
  instances are reachable: weight 700 renders bold but 500 looks like 400.

Notes:

- Qt stores letter spacing in 1/64 px steps (0.15 reads back as 0.140625), so tracking tokens are
  rounded by up to 0.016 px. Harmless; tests allow for it.
- Emphasized styles also change letter spacing (`bodyLarge` 0.5 px vs `bodyLargeEmphasized` 0.15 px),
  so an Emphasized line can be *narrower* than its regular twin. Width tests must neutralize tracking.
