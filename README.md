# Rutile Shell

A Quickshell-based desktop shell for niri that recreates the Googlebook /
ChromeOS look using Material 3 Expressive, with a settings app and desktop
widgets that a local LLM (Ollama / Gemma) can create from a documented spec.

Status: **0.3.1, foundations only.** Design tokens, the matugen palette pipeline
and the QML token singletons (Colors, Shapes, Motion, Type, Elevation, Spacing,
Spring) with the checks every later commit has to pass. No UI yet.

## Layout

| Path | Purpose |
|---|---|
| `tokens/` | M3E tokens: vendored sources, checksums, generated `m3e.json` |
| `theme/` | matugen config + template, role list, golden palette fixture |
| `tools/` | `gen_tokens.py`, `gen_qml.py`, `palette.py`, `qtws.py`, `lint_hardcoded.py` |
| `tests/` | unit tests (stdlib `unittest`) |
| `shell/common/` | QML singletons (mostly generated), `Spring`, `PaletteWatcher` |
| `tests/qml/` | QML tests, run offscreen by `tools/qtws.py` |
| `settings/` `widgets/` `nix/` | empty for now, see roadmap |

## Checks

    make check     # token + generated-QML freshness, tests (incl. QML), lint, qmllint
    make generate  # regenerate shell/common singletons after changing tokens/roles

Tests that need matugen, `materialyoucolor` (optional, test-only) or the Qt tools
(`qmltestrunner`, `qmllint`) skip with a message when they are missing, so check
the skipped count. See `docs/qml.md`. Visual and compositor behavior can only be verified on a real
niri session.

## Tokens

`tokens/m3e.json` holds shape corners, motion springs (expressive and standard),
durations, easings, elevation and the type scale including emphasized styles.
It is generated from androidx Compose Material3 token sources, not scraped from
m3.material.io. Change tokens by refreshing sources (`tools/gen_tokens.py
--refresh`), reviewing the diff and regenerating, never by editing the JSON.

Colors are not here: they come from matugen at runtime, see `docs/theme.md`
(which also records how matugen's output compares to the 2025 color spec).

## License

MIT, see `LICENSE`. Third-party notices are in `NOTICE`.

## Development

    nix develop      # git, make, python (+ materialyoucolor), matugen, qtdeclarative, quickshell
    make check

The dev shell exists because a bare `qtdeclarative` in a nix shell leaves Qt's
QML modules off the import path (`module "QtQuick.Window" is not installed`).
It exports `QML2_IMPORT_PATH` from nixpkgs' own prefix. It deliberately does not
set `QT_QPA_PLATFORM`, so Quickshell launched from it opens real windows; the
test tool sets offscreen itself.

Flakes only see git-tracked files. The first `nix develop` writes `flake.lock`;
commit it so everyone shares one nixpkgs. `make flake-check` evaluates the flake.
Outside nix, `tools/qtws.py` also derives the QML import path from the Qt tool's
install prefix; override with `RUTILE_QML_IMPORT` if your layout is unusual.
