# Handoff: start here

This is the single entry point for anyone picking Rutile Shell up from the git bundle alone: a new Claude
chat, a different AI, a local model, or a person. **The repository is the source of truth.** Claude's
memory is only a cache of it. Keep them in step: when you finish something or change the plan, update
`docs/PLAN.md` (and `CHANGELOG.md` for anything released), and if you have a memory store, update its copy
too. Never leave progress only in memory or only in a chat.

Read in this order: this file, `docs/PLAN.md` (what is done and what is next), `docs/DECISIONS.md` (why things
are the way they are), `docs/LESSONS.md` (traps already hit and how they were found), then the area you will touch.

## 1. What this is

Rutile Shell is a Quickshell (QML) desktop shell for the niri compositor that recreates the Googlebook /
ChromeOS look with Material 3 Expressive (M3E): a bottom shelf, desktop icons and widgets, Quick Settings, a
launcher, and a Settings app, plus a widget system that a local LLM can drive from a documented JSON spec.
It ships as a NixOS flake first; COPR, PKGBUILD and Universal Blue come much later. MIT licensed.

The visual goal is fidelity to the Googlebook screenshots and to the M3E specification. Reference
implementations for structure (not look) are DankMaterialShell (settings, quick-settings tiles, launcher) and
Noctalia. Both are MIT, so logic may be ported with attribution. Caelestia is GPL-3.0: read it, never copy it.

## 2. State right now

Last tagged release: **v0.5.1**. Untagged commits sit on top of it; `CHANGELOG.md` lists them under
Unreleased. There is no shell UI yet: what exists is the foundation and the first components.

| Area | State |
|---|---|
| Design tokens (shape, motion, type, elevation, component specs) | done, generated from vendored Compose Material3 sources |
| Palette pipeline (matugen to `palette.json`) | done; matugen's 2021-era color spec is accepted for now |
| QML singletons: Colors, Shapes, Motion, Type, Fonts, Elevation, Spacing, Spring; EffectsColor/EffectsNumber | done |
| Fonts: Google Sans Flex (text), Material Symbols Rounded (icons) | done |
| Components: Surface, StateLayer, Icon, Button, IconButton, Switch, Slider, ProgressBar, Tile, Chip, ListItem | done, in the gallery |
| Component gallery (`quickshell -p shell/gallery.qml`, offscreen render tool) | done; opens in real Quickshell |
| Remaining components, EditableGrid, shell, widget renderer, settings, distro | not started (see plan) |
| Local-model side-work tooling (opencode 2.x on Ollama, ownership guard) | built; tested end to end against the real opencode 2.1.1 with a scripted model |
| `tools/widget_check.py` (widget schema and widget checker, stdlib) | done; the acceptance check of the widget tasks |
| Widget spec v1 (`widgets/spec.schema.json`, examples) | done: local-model draft merged as failing, rewritten by Claude (plan 4.1, S2) |

Verified, and where: logic and rendering are tested offscreen on Qt 6.12 (the dev shell's Qt, the one the flake's
Quickshell 0.3.2 is built on; Qt 6.7 is the minimum, D31), plus the real OpenGL scene graph under Xvfb and Mesa. The maintainer's machine (NixOS, Qt 6.11.2)
ran the suite and the gallery, and (October 2026) the opencode 2.1.1 checks and the first local-model trial.
**Not verified:** how the gallery looks in a real session to the maintainer, whether the trial ran fully on the GPU
(ROCm), the opencode TUI (only `opencode run` is driven by tests), and every Phase 2 onward item.

Known visual gaps in the components: no ripple, no elevation shadow (elevated buttons are faint on dark
surfaces), no focus ring. See `docs/components.md`.

### Next up

1. The maintainer tries the editable grid in the gallery ("Editable grid"), and reviews Tile, Chip and ListItem.
   Then: the Googlebook signature pieces (ShapeMorph, GeminiGlow), or the large expressive slider the Quick
   Settings panel needs (`docs/reference/README.md`), on the way to Quick Settings (2.6).
2. Next local-model task with the new gates: `widget-templates` (needs the schema, now on main) or `llm-docs`.
   `sidework.py start TASK`, `agent TASK`; commits are refused until the brief's check passes; then
   `sidework.py merge TASK --close`. Judge speed and whether ROCm runs on the card.
3. Finish the component kit (plan item 1.5), then Phase 2.

## 3. Resume in five minutes

Get the repo from the bundle (a bundle is a git repository in one file):

```
git clone rutile-X.Y.Z.bundle rutile            # first time
git pull ../rutile-X.Y.Z.bundle main            # later: update an existing clone
git fetch --tags ../rutile-X.Y.Z.bundle 'refs/tags/*:refs/tags/*'     # pull does not bring tags
```

On the maintainer's NixOS: `nix develop` provides everything (Qt with its QML path, matugen, Quickshell,
Python with materialyoucolor, git, make, the fonts). Then:

```
make check                  # the gate for every commit: generation freshness, tests, lint, qmllint
python3 tools/palette.py render --seed '#134aae' --out ~/.cache/rutile/palette.json
quickshell -p shell/gallery.qml                       # look at the components
python3 tools/qtws.py render --out render --mode dark # or light: offscreen PNG slices instead
make check-gpu              # glyph rendering through the real scene graph (needs a display session)
```

In a bare Linux sandbox without Nix, run `tools/dev/setup_sandbox.sh` and export what it prints; see section 7.

`make check` passing means every test passed or skipped *with a printed reason*. Read the skip lines: a
skip means that tool was missing, not that the behavior was checked.

## 4. Working agreement (what the maintainer asked for)

- **Understand, don't just receive.** Explain the reasoning behind solutions. Work in small guided
  increments the maintainer can run and judge. Be concise and technical.
- **Git identity** for Claude's work: `user.name claude`, `user.email claude@anthropic.com`. The local model
  commits as `local-model <local-model@localhost>`.
- **Test and validate every commit.** `make check` must pass. Beyond that: break the code on purpose
  (mutation testing) and confirm the tests fail; a test that cannot fail proves nothing. Verify claims against
  the real tool (real opencode, real matugen, real fonts, real Qt) instead of memory.
- **Never edit generated files.** Change the source and run `make generate` (and `tools/gen_tokens.py`,
  `tools/gen_components.py` for tokens). `make check` fails on stale output.
- **No hardcoded design values in QML** (colors, radii, durations): use the singletons. A lint enforces it.
- **Light on memory, always** (D31, `docs/memory.md`): create things when they are needed and unload them when
  closed, animate on the property, prefer Rectangles to Canvas, nothing runs while idle. Measure new components
  with `tools/dev/memcost.py`. The lint catches the mechanical cases.
- **No new dependency without the maintainer's approval.** Optional test-only tools that skip when absent are fine.
- **Ask before changing the plan.** Decisions are in `docs/DECISIONS.md`; reverse one only with the reason.
- **Releases:** a release-tag-worthy commit gets a version tag and a git bundle given to the maintainer. Other
  commits are untagged; they still need a bundle to reach the maintainer, named `rutile-dev-<shortsha>.bundle`.
  Never move or reuse a tag the maintainer already has. **Exception:** when working directly in the maintainer's
  checkout (Claude Code on their machine), just commit; no bundle is needed (the maintainer's instruction).
- **Record progress** in `docs/PLAN.md` and `CHANGELOG.md`, and in memory if you have it, in the same session.

### Release protocol

```
make check
git add -A && git -c user.name=claude -c user.email=claude@anthropic.com commit -m "..."
git tag -a vX.Y.Z -m "..."                                  # tag-worthy only
git bundle create rutile-X.Y.Z.bundle --all                 # untagged: rutile-dev-$(git rev-parse --short HEAD).bundle
git bundle verify rutile-X.Y.Z.bundle
git clone rutile-X.Y.Z.bundle /tmp/fresh && (cd /tmp/fresh && make check)      # a fresh clone must pass
# and from the maintainer's previous state:
git clone rutile-<previous>.bundle /tmp/inc && cd /tmp/inc && git pull ../path/rutile-X.Y.Z.bundle main && make check
```

Amending or moving a tag is fine only while nothing has been delivered. If something went out, add a commit.

## 5. Who works on what

Two lines of work exist so that Claude's usage limits do not stop progress.

- **Claude / the main line** owns everything except the local model's area.
- **The local model** (opencode + Ollama on the RX 9060 XT) works on `local/<task>` branches in separate
  worktrees, and only in the paths listed in `tools/ownership.json` (`widgets/**`, `docs/llm/**`). A commit
  hook enforces this; the rules cannot be edited from inside its worktree. While a local branch is open the
  main line does not touch those paths, so merges cannot conflict. Full detail: `docs/sidework.md`. Task
  briefs: `docs/sidework/tasks/`. The conventions the model reads: `docs/sidework/CONVENTIONS.md`.

If you are the local model: read `docs/sidework/CONVENTIONS.md` and your task brief, not the rest of this file.

## 6. Map of the repo

| Path | What it is |
|---|---|
| `shell/common/` | QML singletons (most generated by `tools/gen_qml.py`), `Spring`, `EffectsColor`, `EffectsNumber`, `PaletteWatcher` |
| `shell/components/` | Surface, StateLayer, Icon, Button, IconButton, Switch, Slider, ProgressBar, Tile, Chip, ListItem |
| `shell/gallery.qml`, `shell/gallery/` | the component gallery (window and content) |
| `tokens/` | vendored Compose Material3 token sources with checksums, generated `m3e.json` and `components.json` |
| `theme/` | matugen config and template, required color roles, golden palette, `fonts.json` |
| `nix/` | `googlesans-flex.nix` (our font package), `local-ai-module.nix` (Ollama as a NixOS service) |
| `widgets/` | the widget spec (`spec.schema.json`) and examples; templates come from the local model line |
| `tools/` | generators, `palette.py`, `qtws.py` (Qt test workspace), `fontconf.py`, `otinfo.py`, `sidework.py`, `lint_hardcoded.py` |
| `tools/dev/` | optional dev helpers: `memcost.py` (memory per component), `pyside_qml.py`, `eval_flake.sh`, `setup_sandbox.sh` |
| `tests/` | Python tests; `tests/qml/` offscreen QML tests; `tests/qml_optional/` needs real fonts; `tests/qml_gpu/` needs a display; `tests/qml_render/` renders the gallery |
| `docs/` | this handoff, plan, decisions, lessons, and per-area docs (`components.md`, `memory.md`, `qml.md`, `fonts.md`, `theme.md`, `sidework.md`) |
| `flake.nix` | dev shells (`default`, and x86_64-only `local-ai`), the font package, the NixOS module |

Tool inventory (every script has a docstring with usage): `tools/gen_tokens.py` and `tools/gen_components.py`
generate token JSON from the vendored Kotlin sources; `tools/gen_qml.py` generates the QML singletons;
`tools/palette.py` renders and validates `palette.json`; `tools/qtws.py` builds the Qt workspace and runs
tests, lint, GPU tests and gallery renders; `tools/fontconf.py` writes the dev shell's fontconfig;
`tools/otinfo.py` reads font names and axes; `tools/lint_hardcoded.py` enforces the no-hardcoded-values rule and
the memory rules; `tools/dev/memcost.py` measures memory per component;
`tools/sidework.py` runs the local-model workflow; `tools/widget_check.py` checks the widget schema and widget files; `tools/llm_docs_check.py` checks
the LLM reference documents (task `llm-docs`) against the QML source.

## 7. Environment

### The maintainer's machine

NixOS (unstable), Qt 6.11.2 system-wide (the flake's dev shell has Qt 6.12 and Quickshell 0.3.2), matugen 4.2.0,
niri, Quickshell 0.3.1 (from nixpkgs), a Radeon RX 9060 XT with 16 GB,
Ollama Cloud for LLM work today and local Ollama intended. The repo lives in a `nix-shell`/`nix develop`
checkout; the first `nix develop` writes `flake.lock`, which should be committed.

### Recreating Claude's sandbox

Claude's sandbox is Ubuntu 24.04 with no Nix daemon and a rate-limited GitHub API. `tools/dev/setup_sandbox.sh`
installs what is needed and prints the exports. What it provides, and why each piece mattered:

- Ubuntu's Qt 6.4 tools are **no longer enough**: the code needs Qt 6.7+ (D31). Run the QML tests with
  PySide6 via pip (Qt 6.12) through `tools/dev/pyside_qml.py`.
- Xvfb and Mesa: the **real OpenGL scene graph** headless. The software renderer ignores `renderType`, which hid a bug.
- matugen 4.2.0, the two fonts and `materialyoucolor`, so tests check the real tools. Not opencode: npm's
  `opencode-ai` stops at 1.x, so the real-opencode tests skip there unless `RUTILE_OPENCODE` names a 2.x binary.
- `nix-bin` for evaluating the flake (`tools/dev/eval_flake.sh`); it cannot build, only evaluate.

### Environment variables

| Variable | Used by | Meaning |
|---|---|---|
| `RUTILE_QT_BIN` | `tools/qtws.py` | directory with `qmltestrunner` and `qmllint`; authoritative when set (empty means "no Qt tools") |
| `RUTILE_QML_IMPORT` | `tools/qtws.py` | extra QML module directories (nix shells need Qt's `qml` directory) |
| `RUTILE_MATUGEN` | tests | matugen binary when it is not on `PATH` |
| `RUTILE_FONT_DIRS` | tests, `tools/fontconf.py`, flake | font directories; the font tests run only if they find the real files |
| `RUTILE_OPENCODE` | tests | opencode binary for the real-config checks |
| `RUTILE_OPENCODE_STALL` | tests | seconds without a model request before a real-opencode run counts as hung (default 20) |
| `RUTILE_PALETTE` | `shell/common/PaletteWatcher.qml` | `palette.json` path, default `~/.cache/rutile/palette.json` |
| `RUTILE_SANDBOX` | `tools/dev/setup_sandbox.sh` | where the setup script downloads to |
| `OLLAMA_HOST` | `tools/sidework.py` | Ollama address, default `127.0.0.1:11434` |
| `OPENCODE_CONFIG_CONTENT` | set by `tools/sidework.py agent` | inline opencode config, merged after any project file |

## 8. Resume prompt for a new chat

Upload the latest bundle and say:

> This is the Rutile Shell project. Read `docs/HANDOFF.md`, then `docs/PLAN.md`, and continue from "Next up".
> Follow the working agreement in the handoff. Update the plan, changelog and your memory as you go.

A different AI or person can use the same instruction. Everything needed is in the repo.

## 9. Open questions for the maintainer

- How does the gallery look in a real session, compared with the Googlebook references? (Ripple, shadows and the
  focus ring are deliberately not done yet.)
- Which component batch next: Switch/Slider/ProgressBar, or ShapeMorph/GeminiGlow?
- After the `widget-schema` rerun: is the local line worth keeping, and on which tier? ROCm on the 9060 XT still
  needs checking (`ollama ps` while a model is loaded).
- Plan item 0.2: Googlebook screenshots of Quick Settings, the launcher and Settings are still missing.
- Plan item 1.1b: default seed color and scheme type, chosen against the references.
