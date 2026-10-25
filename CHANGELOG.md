# Changelog

Releases are git tags with a bundle given to the maintainer. Work after the latest tag is under Unreleased and
ships as an untagged `rutile-dev-<sha>.bundle`. Every tag must have a section here (a test checks).

## Unreleased

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

- **opencode 2.x** for the local agent (the maintainer's switch, c62dbf8, finished): the generated config follows
  the real 2.1.1 schema (`providers` with `package`, ordered `permissions`, `policies`); the launcher runs
  `--standalone`, sets `PWD` to the worktree and removes the `execute` tool. The draft 2.x config could not run
  (`Unsupported package`), and without `PWD` the agent would have worked in the main checkout. Real-opencode tests
  now drive 2.1.1 end to end through a scripted fake model, including a hostile project `opencode.json`.
- **`tools/widget_check.py`**: stdlib checker for the widget schema and widget files, the acceptance check of the
  `widget-schema` brief; refuses JSON Schema keywords it does not implement. `sidework.py check` and `status`
  report uncommitted leftovers in a worktree. `tools/llm_docs_check.py` does the same job for the `llm-docs` task.
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
