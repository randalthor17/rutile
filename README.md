# Rutile Shell

**Resuming this project (new session, new person, or a different AI)? Start with `docs/HANDOFF.md`.**

**Installing it (Nix flake, home-manager): see `docs/install.md`.**

A Quickshell-based desktop shell for niri that recreates the Googlebook /
ChromeOS look using Material 3 Expressive, with a settings app and desktop
widgets that a local LLM (Ollama / Gemma) can create from a documented spec.

Status: **0.11.0** (`CHANGELOG.md`; 0.6.0 to 0.10.0 were tagged afterwards at their milestones). The shell runs as a
whole desktop on niri: a top bar (clock with a calendar, status pill, notification bell, app indicators), Quick
Settings, the shelf and launcher, notifications, OSD and toasts, the lock screen, power menu and polkit agent, the
wallpaper with its palette, desktop widgets, and the Settings and Widgets apps. It installs from the flake as a
package and a home-manager module, with a greetd sign-in screen (`docs/install.md`). Still to come: an installer ISO
(`docs/PLAN.md`).

## Layout

| Path | Purpose |
|---|---|
| `shell/shell.qml` | the shell's entry point: every window, popup and IPC target |
| `shell/common/` | QML singletons (mostly generated), `Spring`, `EffectsColor`, `EffectsNumber`, `PaletteWatcher` |
| `shell/components/` | the M3E kit: buttons, switch, slider, progress, tile, chip, list item, menu, text field, dialog, FAB, card, ShapeMorph, EditableGrid, title bar (`docs/components.md`) |
| `shell/bar/`, `shell/calendar/` | the top bar, and the calendar under the clock |
| `shell/quicksettings/`, `shell/shelf/`, `shell/launcher/` | Quick Settings (`docs/quick-settings.md`), the shelf, the launcher |
| `shell/notifications/`, `shell/osd/`, `shell/toast/` | notifications, the volume and brightness OSD, toasts |
| `shell/lock/`, `shell/power/`, `shell/polkit/`, `shell/wallpaper/` | the lock screen, power menu, polkit agent, wallpaper |
| `shell/greeter.qml`, `shell/greeter/` | the sign-in screen on greetd (`nixosModules.greeter`) |
| `shell/settingsapp/`, `shell/widgetsapp/` | the Settings app (`docs/settings.md`) and the Widgets app |
| `shell/widgethost/`, `shell/desktop/` | the widget renderer and data sources, the desktop widget grid (`docs/widgets.md`) |
| `shell/services/` | Quickshell service wrappers (audio, network, Bluetooth, niri...) and the settings store |
| `shell/gallery.qml`, `shell/gallery/` | the component gallery |
| `settings/schema.json` | every setting, read by the shell and the home-manager module |
| `widgets/` | the widget spec, the data sources' catalog, examples and templates |
| `tokens/`, `theme/` | M3E tokens (vendored sources, generated JSON); matugen config, templates, roles, fonts |
| `native/` | the C programs: the Firefox colors' host and the calendar's evolution-data-server reader (`make native`) |
| `bin/rutile-shell` | the command: runs the shell and calls it over IPC (`rutile-shell --help`) |
| `nix/` | the package, the home-manager module, the Google Sans Flex package, the local-AI NixOS module |
| `tools/` | generators, `qtws.py` (tests, lint, renders, headless runs), `widget_check.py`, `lint_hardcoded.py` |
| `tests/` | Python tests; `tests/qml/` offscreen QML tests; `tests/qs/` tests under Quickshell |

## Checks

    make check     # token + generated-QML freshness, tests (incl. QML), lint, qmllint
    make generate  # regenerate shell/common singletons after changing tokens/roles

Tests that need matugen, `materialyoucolor` (optional, test-only) or the Qt tools
(`qmltestrunner`, `qmllint`) skip with a message when they are missing, and the
font checks skip unless `RUTILE_FONT_DIRS` finds the font files (the devshell
sets it), so check the skipped count. See `docs/qml.md` and `docs/fonts.md`. Visual and compositor behavior can only be verified on a real
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

    nix develop      # git, make, python, matugen, Qt's QML tools, quickshell, the runtime tools, libecal
    make check

The dev shell exists because a bare `qtdeclarative` in a nix shell leaves Qt's
QML modules off the import path (`module "QtQuick.Window" is not installed`).
It exports `QML2_IMPORT_PATH` from nixpkgs' own prefix. It deliberately does not
set `QT_QPA_PLATFORM`, so Quickshell launched from it opens real windows; the
test tool sets offscreen itself.

Flakes only see git-tracked files. `flake.lock` is committed, so everyone shares one nixpkgs. `make flake-check` evaluates the flake.
Outside nix, `tools/qtws.py` also derives the QML import path from the Qt tool's
install prefix; override with `RUTILE_QML_IMPORT` if your layout is unusual.

## Try it

    nix develop
    make native                                                # the C helpers the shell runs
    quickshell -p shell/shell.qml                              # the shell, on niri (one instance at a time)
    quickshell -p shell/gallery.qml                            # the component gallery
    python3 tools/qtws.py test-wayland                         # the whole shell under a headless sway

See `docs/install.md` to install it, `docs/components.md` for the kit.

## Side work with a local model

`tools/sidework.py` runs a local Ollama model on bounded tasks in separate worktrees, in paths the main
line of work does not touch, with commit-time enforcement. `nix develop .#local-ai` provides Ollama
(ROCm) and opencode; `nixosModules.local-ai` runs Ollama as a service. See `docs/sidework.md`.
