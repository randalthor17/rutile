# Changelog

Releases are git tags with a bundle given to the maintainer. Work after the latest tag is under Unreleased and
ships as an untagged `rutile-dev-<sha>.bundle`. Every tag must have a section here (a test checks).

## Unreleased

- **Slider end icon near full** (maintainer's Android 17 reference): when the inactive part of the track gets
  too short, the end icon moves to the end of the active part, beside the handle, in the active icon color,
  instead of disappearing. A slider with an end icon no longer shows the stop dot at all. The gallery's
  brightness row sits near full to show it, and its size demos carry one end icon, as Android's sliders do.
- **Fix:** right to left, a Tile's Latin labels sat against the far edge of the tile (8 px) instead of beside
  the icon. Qt aligns unaligned text by its script, which LayoutMirroring does not flip; the labels now set
  their alignment, so it mirrors.
- **Expressive slider sizes and track icons** (plan 1.5e, D36): `Slider` takes `size` (`xs` default, `s`, `m`,
  `l`, `xl`: 16 to 96 px tracks) and, from `m` up, `startIcon` and `endIcon` inside the track, each shown only
  while its part of the track has room; the end icon replaces the stop dot. Larger sizes shrink their corners on
  a short part instead of hiding it. The slider now mirrors under `LayoutMirroring`. Sizes come from Material
  Components Android's slider tokens, vendored and checksummed next to the Compose files. The gallery shows the
  sizes and Quick Settings' brightness and volume rows. A slider without icons costs 79.5 KiB (was 71.6).
- **Fix:** `tools/qtws.py test` reported a run with exactly three failures as skipped and exited 0, because its
  "skipped" code was 3 and qmltestrunner exits with the failure count. `make check` was not affected (it checks
  the counts). The sentinel is no longer a number.
- **`docs/editable-grid.md`**: the grid's full behavior in one place, with diagrams and the test that pins each
  rule (layout without gaps, select, drag and drop, resize with shrinking neighbors, row limit, adding, right to
  left, motion and memory). `make check` fails if it cites a test that no longer exists, or a missing path.
- **No gaps in the Quick Settings grid** (D35, maintainer's rule): with gravity, tiles flow in reading order,
  so gaps at the top, at a row's start and between tiles close as the tiles behind slide forward, and the next
  row's first tile moves up into the free end of the row above. Nothing stretches; free space is left only at
  the end of a row. Tiles without a saved position join at the end, and `fitNew` uses the same flow. Before,
  gravity only pulled tiles up, so a later tile could jump ahead into a hole. 2 new QML tests.
- **Grid resizing from every side** (D34, maintainer's bug report): a neighbor in the way of a resize now
  shrinks down to its minimum before it moves (before, it always moved). The selected item shows a handle on
  each side that can move (before, only the right edge), every item can grow to the full width and in height,
  and the grid and the Tile mirror for right-to-left locales through `LayoutMirroring` (icon on the right).
  The gallery's grid has a right-to-left switch. Handles now exist only on the selected item, so edit mode
  costs about 11 KiB per slot instead of 29. 6 new QML tests; a 20-fault mutation run caught every fault after
  two more.
- **EditableGrid** (plan 1.6): the grid under Quick Settings tiles and later desktop widgets. Packing ported from
  DankMaterialShell's `GridLayout.js` (MIT, in `NOTICE`). In edit mode: click to select, drag to move (the rest
  make room around a placeholder), a resize handle within each item's limits and `maxRows`; changes go through
  `commitHandler`. Delegates survive reorders, the edit chrome exists only while editing, one spring moves
  everything. A 9-tile grid costs about 28 KiB per slot over the tiles. 14 new QML tests plus a gallery test;
  a 15-fault mutation run caught every fault after four more tests.
- **Toggles show the applied state** (D33). Switch, Tile and filter Chip take `controlled: true`: a click
  emits `toggled(wanted)` and changes nothing, and the control follows its bound state, so a setting that
  fails to apply never shows as changed. One new QML test drives all three against a stand-in backend.
- **Googlebook references** in `docs/reference/` with notes per part (Quick Settings and its edit mode,
  Settings, desktop). The Quick Settings tile matches Android 16's, so the Tile stays as built (D32).
- **Tile, Chip, ListItem** (plan 1.5d). Tile: Android 16's Quick Settings tile (D32): pill when inactive, 24 px
  corners when active, large or icon-only, dual-target (icon toggles, body opens details), unavailable state.
  Chip: assist (flat or elevated) and filter (check when selected), with Compose's spacing. ListItem: one or
  two lines, leading icon, trailing text and a slot for a control, expressive shape morph (4/12/16 px), and
  segmented groups that keep their outer corners. Values from AssistChipTokens, FilterChipTokens, ListTokens,
  ListItemDefaults.kt, Chip.kt and SystemUI's Tile.kt/CommonTile.kt (vendored; `gen_tokens.py --refresh`
  decodes googlesource's base64). `StateLayer` takes per-corner radii. 16 new QML tests; a 15-fault mutation
  run caught every fault.
- **Test fix:** `make check-gpu` failed on one pixel. The glyph was solid; the test sampled a square whose
  corner reached the heart's slanted edge once Qt 6.12 placed the glyph 1 px differently. It samples a disc now,
  as its comment said, and still fails with the old (holey) text rendering.
- **Lighter components** (D31, `docs/memory.md`): colors and opacities animate with Qt animations on the
  effects-spring curve (`EffectsColor`, `EffectsNumber`; the curve is fitted in `tools/gen_qml.py` and checked)
  instead of a JavaScript spring object each; Slider and ProgressBar draw with Rectangles, the wave's Canvas
  exists only while it shows; Button and Switch create icons only when they have one. Per instance: Surface
  17 to 6 KiB, Slider 140 to 72, Switch 125 to 90, Button 84 to 62. `SpringColor` is removed.
  `tools/dev/memcost.py` measures; the lint now fails on an eager Canvas, an Image without `sourceSize` and an
  always-running FrameAnimation.
- **Qt 6.7 is the minimum** (D31; the flake's Quickshell is on Qt 6.12). Qt 6.4 workarounds are gone, and
  `qmllint` reports no warnings (14 before).
- **Switch, Slider, ProgressBar** (plan 1.5c). Switch: 52x32, handle 16/24/28 px with optional icons, snaps while
  pressed and springs on release. Slider: expressive track with a 6 px gap around a 4x44 handle that narrows to
  2 px while pressed or focused, stop and tick dots, steps, keyboard. ProgressBar: linear determinate, flat or
  wavy (the wave moves one wavelength per second and flattens below 10% and from 95%), progress eased with
  Compose's spring. Specs come from five more vendored token files plus values parsed from `Slider.kt`,
  `ProgressIndicator.kt` and `WavyProgressIndicator.kt`; the generator fails if those change. `StateLayer` takes
  an external `input` area. In the gallery; 19 new QML tests (18 in `tests/qml/tst_controls.qml`, one in the
  gallery test). A 17-fault mutation run caught every fault.
- **Fix:** the `local-ai` dev shell now has everything the default shell has (Qt, qmltestrunner, Quickshell,
  matugen, `QML2_IMPORT_PATH`, the fonts), so an agent in it can run `make check` and its acceptance check.
- `local-ai` dev shell: Node.js 22, which some local MCP servers need.
- **Fix:** springs stopped following a bound target after their first settle (`Spring` rested via `snap()`, which
  assigns `target` and breaks the binding). Button press morphs, state-layer opacity and the gallery's motion
  lanes only worked once. Found by the maintainer in the gallery.
- **Fix:** filled (selected) toggle icons rendered with holes and streaks. Qt's default distance-field text
  corrupts the overlapping contours of filled Material Symbols glyphs. `Icon` now uses `Text.NativeRendering`.
  Reproduced under Mesa OpenGL on Qt 6.12; a GPU-path test (`tests/qml_gpu/`, `make check-gpu`) and a cheap
  always-on test guard it.
- **Side work with a local model** (`docs/sidework.md`): `tools/sidework.py` (start, agent, prepare, check,
  merge-check, bundle, status, models, serve), a commit-time ownership guard installed from the main checkout,
  flake `local-ai` dev shell (Ollama ROCm, opencode, radeontop) and `nixosModules.local-ai`, model tiers in
  `tools/local_models.json`, conventions and three task briefs. Switched from aider to opencode after the
  maintainer found aider's workflow unusable for agentic work. Found and fixed a hole where the guard read its
  rules from the worktree it was policing.
- **Handoff:** `docs/HANDOFF.md`, `docs/PLAN.md`, `docs/DECISIONS.md`, `docs/LESSONS.md`, this changelog and
  `AGENTS.md`, so the project can resume from the bundle alone. Drift guards in `tests/test_handoff.py`.
- **Dev tools** (`tools/dev/`): `pyside_qml.py` (run the QML tests or render the gallery on a modern Qt via PySide6,
  optionally through the real OpenGL scene graph), `eval_flake.sh`, `setup_sandbox.sh`.

- **Side work cleanup:** `sidework.py merge TASK --close` merges and closes in one step; `close --merged` closes
  every `local/*` branch already in main. Neither deletes uncommitted worktree files without `--force`.
- **opencode 2.x** for the local agent (the maintainer's switch, c62dbf8, finished): the generated config follows
  the real 2.1.1 schema (`providers` with `package`, ordered `permissions`, `policies`); the launcher runs
  `--standalone`, sets `PWD` to the worktree and removes the `execute` tool. The draft 2.x config could not run
  (`Unsupported package`), and without `PWD` the agent would have worked in the main checkout. Real-opencode tests
  now drive 2.1.1 end to end through a scripted fake model, including a hostile project `opencode.json`.
- **`tools/widget_check.py`**: stdlib checker for the widget schema and widget files, the acceptance check of the
  `widget-schema` brief; refuses JSON Schema keywords it does not implement. `sidework.py check` and `status`
  report uncommitted leftovers in a worktree. `tools/llm_docs_check.py` does the same job for the `llm-docs` task.
- **Widget spec v1** (`widgets/spec.schema.json`, plan 4.1): the local model's `widget-schema` draft, merged as
  a recorded failing draft, then rewritten by Claude: recursive `$defs`, `tone` limited to surface roles, unknown
  fields rejected at every level. Five examples; `tests/test_widget_spec.py` pins what the spec refuses.
- **Acceptance gate for local tasks:** each brief declares a runnable check; the commit hook refuses staged work
  that fails it, `sidework.py check` judges the would-be merge result, and the new `sidework.py merge` refuses
  failing branches unless `--accept-failing "why"` (recorded as a TODO in the merge commit). New `sidework.py
  close` removes a merged task's worktree, branch and allowlist. `tools/widget_check.py --templates` checks the
  `widget-templates` rules.
- **Local-model conventions and brief** tightened after the first trial: no installing, files only through the
  edit tools, stop after repeated failures, commit only own paths; the `widget-schema` brief sketches the recursive
  structure.
- **Flake:** `claude-code` in the `local-ai` shell is allowed as the only unfree package; plain `pkgs.claude-code`
  made `nix develop .#local-ai` fail to evaluate.
- **Fix:** the first handoff bundle (`rutile-dev-17ca1a5`) failed `make check` on a clean clone: the docs mentioned
  `widgets/` and `settings/`, which existed only as untracked empty directories. They now hold tracked READMEs, and
  the path check uses `git ls-files` so leftovers cannot mask this again.

## 0.5.1

- Fixed a test that wrongly expected Emphasized type styles to render wider (they also change letter spacing).
  The implementation was right; reproduced on Qt 6.12 from the maintainer's Qt 6.11 failure.
- New tests: `Type.font()` carries exact `wght`/`opsz`; the `FILL` axis adds ink (feature-detected).
- `tools/qtws.py` prints failing assertions first so long output cannot hide the error.

## 0.5.0

- First M3E components: Surface, StateLayer, Icon, Button (5 types x 5 sizes, round/square, toggle), IconButton
  (4 types, width variants), SpringColor; a component gallery (`shell/gallery.qml`) and an offscreen render tool.
- `tools/gen_components.py` generates button and icon-button specs from the vendored Compose tokens; the stale
  XS button token is corrected explicitly and guarded.
- Bugs found and fixed: `Spring.snap()` broke bound targets (added `rest()`); `SpringColor` faded in at creation;
  `Type.styleNames` added because singletons cannot be enumerated.

## 0.4.0

- Fonts: Google Sans Flex through the maintainer's nix package, Material Symbols Rounded; `theme/fonts.json` is the
  source of truth; `Fonts.qml`, `Type.font()`; the dev shell exports the font directories and a generated fontconfig.
- `tools/otinfo.py` reads font names and axes so tests check the real files.

## 0.3.1

- Nix dev shell (`flake.nix`); `tools/qtws.py` finds Qt's QML modules on nix-style installs after the maintainer's
  `QtQuick.Window is not installed` failure on Qt 6.11.

## 0.3.0

- QML singletons: Colors, Shapes, Motion, Type, Elevation (generated), Spacing, Spring (exact M3 spring solver),
  PaletteWatcher. Color roles `on_x` are `xOn` (QML reads `onXxx` as a signal handler).
- Offscreen QML test workspace (`tools/qtws.py`).

## 0.2.0

- matugen palette pipeline: `tools/palette.py`, `theme/matugen.toml`, `palette.json` format 1 with both modes.
- Measured: matugen 4.2.0 implements the 2021-era color spec (94.7% agreement), not the 2025 one.

## 0.1.0

- Scaffold: vendored Compose Material3 token sources with checksums, `tools/gen_tokens.py`, hardcoded-value lint,
  `make check`, MIT license.
