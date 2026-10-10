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

Verified (with the real files, offscreen, Qt 6.4.2): both fonts load into Qt and
report the configured family names; `Type.font()` carries the right family,
size and weight; the `settings` icon ligature renders as one glyph;
fontconfig resolves the family through the generated config.

- Qt stores letter spacing in 1/64 px steps (0.15 reads back as 0.140625), so
  tracking tokens are rounded by up to 0.016 px. Harmless, but tests allow for it.
- Axis control (`ROND`, `opsz`, `wght` beyond named instances, icon `FILL`)
  needs `font.variableAxes`, which Qt 6.4 does not have. A feature-detected test
  checks it where Qt supports it and skips, with its reason, where it does not.
  It has not been run against a Qt that supports it yet.
- How weights 500 and 700 render for the variable font on newer Qt is checked
  visually in the component gallery (plan item 1.7), not assumed.
