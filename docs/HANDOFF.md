# Handoff: start here

This is the single entry point for anyone picking Rutile Shell up from the repository alone
(https://github.com/randalthor17/rutile, public; or a git bundle): a new Claude
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

Last tagged release: **v0.5.1**. About 130 untagged commits sit on top of it; `CHANGELOG.md` lists them under
Unreleased. The shell runs as a whole desktop on niri; `docs/PLAN.md` has each part's state and what is left.

| Area | State |
|---|---|
| Tokens, palette (matugen), QML singletons, fonts | done (Phase 0 and 1) |
| Components (`shell/components/`): buttons, icon buttons, switch, slider, progress, tile, chip, list item, ShapeMorph, EditableGrid, menu, text field, dialog, FAB, card, title bar | done, in the gallery; NavRail and GeminiGlow left (1.5) |
| Top bar: clock with its calendar (D93 to D95), status pill, notification bell, app indicators | working; tested headless and in nested niri |
| Quick Settings: saved tiles, Wi-Fi and Bluetooth pages, Night light (wlsunset), Power saver, Do not disturb | working; real Wi-Fi, Bluetooth and Night light not tried |
| Shelf, launcher, notifications, OSD, toasts, lock screen, power menu, polkit agent, wallpaper | working (Phase 2) |
| Settings app (D50, D92), Widgets app, desktop widgets and their renderer and data sources | working (Phase 4, 5) |
| Windows like Googlebook's (niri window rule, D88) | working, off by default |
| Package, home-manager module, app theming (Phase 6.1) | working; greeter (6.2) and installer ISO (6.3) not started |
| Local-model side work, widget generation | deferred (D82) |

Verified, and where: logic and rendering offscreen on Qt 6.12 (the dev shell's, the one the flake's Quickshell 0.3.2
is built on; Qt 6.7 is the minimum, D31); Quickshell tests offscreen (`tests/qs/`); the whole shell under a
headless sway (`qtws.py test-wayland`) and in nested niri; the package built and run headless (`make
package-check`); the calendar's reader against a real evolution-data-server on a private bus.
**Not verified:** real Wi-Fi, Bluetooth, backlight and Night light; real pointer drags on title bars; a real Google
account (D95); how the shell looks to the maintainer next to the references.

Known visual gaps in the components: no ripple, no elevation shadow (elevated buttons are faint on dark
surfaces), no focus ring. See `docs/components.md`.

### Next up

1. The maintainer tries the shell on the real session with the features together (Quick Settings with real Wi-Fi,
   Bluetooth and Night light; Settings > Windows (D88) with a real pointer; the calendar with a Google account after
   the NixOS services in `docs/install.md`, D95) and reports what looks or works wrong.
2. Phase 6: the greetd greeter in the shell's style (6.2, Quickshell's `Greetd`), then the installer ISO (6.3).
3. Finish the component kit (1.5: NavRail, GeminiGlow once a reference image exists) and the gallery review (1.7).
4. Smaller open parts: hidden Wi-Fi networks (2.6), adding events from the popup, calendar addresses and
   evolution-data-server for widgets.
5. Widget generation and the local-model trial stay deferred (D82).

## 3. Resume in five minutes

Get the repo from GitHub, or from a bundle (a git repository in one file) where GitHub cannot be reached:

```
git clone https://github.com/randalthor17/rutile.git     # the usual way
git clone rutile-X.Y.Z.bundle rutile            # first time
git pull ../rutile-X.Y.Z.bundle main            # later: update an existing clone
git fetch --tags ../rutile-X.Y.Z.bundle 'refs/tags/*:refs/tags/*'     # pull does not bring tags
```

On the maintainer's NixOS: `nix develop` provides everything (Qt with its QML path, matugen, Quickshell,
Python with materialyoucolor and jsonschema, git, make, the fonts). Then:

```
make check                  # the gate for every commit: generation freshness, tests, lint, qmllint
python3 tools/palette.py render --seed '#134aae' --out ~/.cache/rutile/palette.json
quickshell -p shell/gallery.qml                       # look at the components
python3 tools/qtws.py render --out render --mode dark # or light: offscreen PNG slices instead
make check-gpu              # glyph rendering through the real scene graph (needs a display session)
python3 tools/qtws.py test tst_settings_app      # one QML test file (a mutation batch: seconds, not a minute)
make native                 # the Firefox colors' host (C, D54); make check builds it and tests it under ASan/UBSan
make package-check          # nix build .#default, then run it headless in a sandbox HOME (D55; not in make check)
make theming-check          # real GTK/Qt/KDE apps through programs.rutile.theming, screenshots (D59; minutes, network)
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
- **Every popup animates the same way, and every animation follows `Motion.speed`** (D43, the maintainer's
  rule). Dropdowns, menus and panels use `PopupMotion` or `PopupLoader`; motion goes through `Spring`,
  `EffectsNumber`, `EffectsColor` or `Motion.duration()`. The lint rejects raw Qt animations outside
  `shell/common`.
- **Light on memory, always** (D31, `docs/memory.md`): create things when they are needed and unload them when
  closed, animate on the property, prefer Rectangles to Canvas, nothing runs while idle. Measure new components
  with `tools/dev/memcost.py`. The lint catches the mechanical cases.
- **Quickshell first** (the maintainer's rule). Before building anything, read the Quickshell docs for the
  installed version (`quickshell --version`; now 0.3.2, https://quickshell.org/docs/v0.3.2/types/) and use its
  type when one fits; the table "Quickshell types and where they go" below maps them to plan items. Our own code
  is for what Quickshell does not have (M3E controls, shapes, the widget renderer) or a gap it leaves; say which
  in the commit. Code that needs Quickshell types is tested with `tools/qtws.py test-qs` (tests/qs/).
- **No new dependency without the maintainer's approval.** Optional test-only tools that skip when absent are fine.
- **Ask before changing the plan.** Decisions are in `docs/DECISIONS.md`; reverse one only with the reason.
- **Releases:** the repository lives at https://github.com/randalthor17/rutile (`origin`), and its flake is used
  from there (`github:randalthor17/rutile`). Working in the maintainer's checkout (Claude Code on their machine),
  commit and push to `origin`; no bundle is needed. A release-tag-worthy commit also gets a version tag, pushed
  with `git push --tags`. A session that cannot push (a sandbox) hands the maintainer a git bundle instead:
  `rutile-X.Y.Z.bundle` for a tag, `rutile-dev-<shortsha>.bundle` otherwise. Never move or reuse a tag that was
  pushed or delivered.
- **Record progress** in `docs/PLAN.md` and `CHANGELOG.md`, and in memory if you have it, in the same session.

### Quickshell types and where they go

Quickshell 0.3.2. Checked against the docs in October 2026; "in use" is what the repo uses today.

| Need | Quickshell type | Plan |
|---|---|---|
| Shell root, windows | `ShellRoot`, `FloatingWindow` (in use: gallery), `PanelWindow` (in use: Quick Settings), `PopupWindow`, `PopupAnchor`, `QsWindow` | 2.3 to 2.8 |
| Layer-shell surfaces (desktop, shelf, panels) | `WlrLayershell`, `WlrLayer`, `ExclusionMode`, `WlrKeyboardFocus` (in use: status pill, Quick Settings) | 2.3, 2.4, 2.6 |
| Keep windows clear of shell UI | `PanelWindow.exclusiveZone` on a 1 px click-through surface (`mask: Region {}`) (in use: `shell/bar/EdgeExclusion.qml`, D42) | 2.3, 2.4 |
| One surface per monitor | `Variants` over `Quickshell.screens`, `ShellScreen` | 2.3, 2.4 |
| Load windows and popups only while open (D31) | `LazyLoader` (in use: Quick Settings; windows and popups; small in-item parts keep Qt's `Loader`) | 2.4 to 2.8 |
| Files and config, watched | `FileView` (in use: PaletteWatcher, Settings); `JsonAdapter` drops unknown keys, not used for settings (D45) | 2.5, 4.2 |
| Commands, sockets | `Process` (in use: brightnessctl), `StdioCollector`, `SplitParser`, `Socket` | 4.2; 2.2 only as the fallback (D38) |
| Shell IPC and keybinds | `IpcHandler` (in use: `quicksettings`; `quickshell -p ... ipc call` from niri binds) | 2.2 |
| State kept across config reloads | `PersistentProperties` | 2.x |
| Clock | `SystemClock` | 2.3, 4.2 |
| Apps | `DesktopEntries`, `DesktopEntry`, `IconImage` | 2.4, 2.7 |
| Running windows, workspaces | `Quickshell.Niri` once PR #949 merges (D38); `ToplevelManager`, `Toplevel` (wlr-foreign-toplevel) | 2.2, 2.4 |
| Sound | `Pipewire`, `PwNode`, `PwNodeAudio`, `PwObjectTracker` (in use: AudioService) | 2.1, 2.6 |
| Network | `Networking`, `NetworkDevice`, `WifiDevice`, `WifiNetwork` (NetworkManager backend; in use: NetworkService) | 2.1, 2.6, 5.2 |
| Bluetooth | `Bluetooth`, `BluetoothAdapter`, `BluetoothDevice` (in use: BluetoothService) | 2.1, 2.6, 5.2 |
| Battery, power profiles | `UPower`, `UPowerDevice`, `PowerProfiles` | 2.1, 2.6, 4.2 |
| Media | `Mpris`, `MprisPlayer` | 2.1, 2.3 (media pill), 4.2 |
| Notifications | `NotificationServer`, `Notification` | 2.8 |
| Icon theme | `//@ pragma IconTheme`, `Quickshell.iconPath` (in use: Papirus-Dark, D62) | 2.10 |
| Tray and its menus | `SystemTray`, `SystemTrayItem`, `QsMenuOpener` (in use: app indicators, D61); `QsMenuAnchor` (not: the platform menu is not our style) | 2.10 |
| Lock screen, idle | `WlSessionLock`, `WlSessionLockSurface`, `PamContext`, `IdleMonitor`, `IdleInhibitor` | 2.8 |
| Greeter, polkit | `Greetd`, `PolkitAgent` | 6.2, 2.8 |
| Rounded clipping of children (cards, pictures) | `ClippingRectangle` (rectangles only; a cookie needs ShapeMorph) | 2.3, 4.3 |
| Wallpaper colors | `ColorQuantizer` (dominant colors only; matugen still makes the scheme) | 1.1b |
| Blur behind a surface | `BackgroundEffect` (`ext-background-effect-v1`, which niri supports; D38) | 2.3 to 2.8, 3.1 |
| Screen preview | `ScreencopyView` | later |

Not in Quickshell, so ours: the M3E controls and shapes (`shell/components/`), the widget renderer, settings
registry and search. niri IPC: wait for `Quickshell.Niri` (D38). `Quickshell.WindowManager` only speaks
ext-workspace-v1, which is immature, and niri's implementation of it is basic: do not use it for niri.

### Release protocol

```
make check
git add -A && git -c user.name=claude -c user.email=claude@anthropic.com commit -m "..."
git tag -a vX.Y.Z -m "..."                                  # tag-worthy only
git push origin main --tags                                 # in the maintainer's checkout; done here
# a session that cannot push gives a bundle instead:
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
| `shell/components/` | Surface, StateLayer, Icon, Button, IconButton, Switch, Slider, ProgressBar, Tile, Chip, ListItem, EditableGrid, ShapeMorph |
| `shell/shell.qml` | the shell's entry point (`quickshell -p shell/shell.qml`): palette watcher, Quick Settings, IPC |
| `shell/services/` | Quickshell service wrappers: audio, network, Bluetooth, brightness (`docs/quick-settings.md`), niri; `Settings` (the settings and state files, `docs/settings.md`) |
| `shell/settingsapp/` | the Settings app (D50): the registry `Pages.js`, `Model.js`, rows, the window; `shell/settingsapp/pages/` holds pages of their own, each a view and maybe a backend (D67) |
| `shell/quicksettings/` | the Quick Settings panel, its tiles (`Controls.js`), the Wi-Fi and Bluetooth pages (`Details.js`), its backend and window |
| `shell/desktop/` | the desktop widget grid (plan 4.4, D81): `DesktopWindow` per screen on the bottom layer, `DesktopWidgets` (EditableGrid and the edit bar), `WidgetLibrary` reads the placed files, `Desktop.js` the saved layouts |
| `shell/widgetsapp/` | the Widgets app (plan 4.5, D82): `WidgetsWindow` reads `widgets/templates` and the user's widgets, `WidgetsApp` the categories and `WidgetCard`s, `Gallery.js` the rules |
| `shell/widgethost/` | charts (D87): `ChartNode.qml`; the widget check (4.6, D85): `WidgetCheck.js`, the port of `tools/widget_check.py`, and `WidgetChecker` for IPC; the widget renderer (plan 4.3, D78): `WidgetHost` draws a spec from `widgets/`, `WidgetSpec.js` fills bindings; the data sources (4.2, D79): `WidgetSources` loads the ones a widget binds from `shell/widgethost/sources/`, `Sources.js` works out their values |
| `shell/bar/` | the top bar: the clock (opens the calendar), the status pill (opens Quick Settings), the bell, app indicators, and their windows |
| `shell/calendar/` | the calendar under the clock (D93 to D95): `Calendar.js` (iCalendar, repeats, the month), the panel and window, `CalendarFeeds` (calendar addresses), `EdsCalendar` (evolution-data-server through `build/rutile-calendar`) |
| `shell/notifications/` | notification cards, the popup stack, the list panel and their windows (D47); the server is `shell/services/NotificationService.qml`, the bell `shell/bar/NotificationBell.qml` |
| `shell/osd/`, `shell/toast/`, `shell/lock/`, `shell/wallpaper/`, `shell/power/` | the volume and brightness OSD, toasts (`ToastService`), the lock screen (WlSessionLock and PAM), the wallpaper (`WallpaperService`), the full-screen power menu |
| `shell/gallery.qml`, `shell/gallery/` | the component gallery (window and content) |
| `tokens/` | vendored Compose Material3 token sources with checksums, generated `m3e.json` and `components.json` |
| `theme/` | matugen config and template, required color roles, golden palette, `fonts.json` |
| `settings/` | `schema.json`: every setting of the shell, read by the shell and the home-manager module (D45) |
| `nix/` | `package.nix` (the shell's package, D55), `googlesans-flex.nix` (our font package), `local-ai-module.nix` (Ollama as a NixOS service), `home-manager.nix` (`programs.rutile`: the service, niri's part, the settings) |
| `widgets/` | the widget spec (`spec.schema.json`), the data sources' catalog (`sources.json`) and examples; templates come from the local model line |
| `tools/` | generators, `palette.py`, `qtws.py` (Qt test workspace), `fontconf.py`, `otinfo.py`, `sidework.py`, `lint_hardcoded.py` |
| `tools/dev/` | optional dev helpers: `memcost.py` (memory per component), `package_smoke.py` (the built package, headless; `make package-check`), `theming_check.py` and `theming-home.nix` (GTK, Qt and KDE apps in the shell's look through `programs.rutile.theming`, screenshotted in a sandbox; `make theming-check`, D59), `pyside_qml.py`, `eval_flake.sh`, `setup_sandbox.sh` |
| `bin/rutile-shell` | the `rutile-shell` command (D57): runs the shell, calls it over IPC, `--help` lists every call; `flatpak-theming` (D66) |
| `native/` | the C programs: the Firefox colors' host (D54) and the calendar's evolution-data-server reader (D95); `make native` builds `build/rutile-pywalfox-host` and `build/rutile-calendar` |
| `tests/` | Python tests; `tests/qml/` offscreen QML tests; `tests/qs/` tests run under `quickshell` (fake `brightnessctl` in `tests/qs/bin/`); `tests/qml_optional/` needs real fonts; `tests/qml_gpu/` needs a display; `tests/qml_render/` renders the gallery |
| `docs/` | this handoff, plan, decisions, lessons, and per-area docs (`components.md`, `editable-grid.md`, `quick-settings.md`, `memory.md`, `qml.md`, `fonts.md`, `theme.md`, `sidework.md`, `settings.md`) |
| `flake.nix` | dev shells (`default`, and x86_64-only `local-ai`), the font package, the NixOS module, the home-manager module |

Tool inventory (every script has a docstring with usage): `tools/gen_tokens.py` and `tools/gen_components.py`
generate token JSON from the vendored Kotlin sources; `tools/gen_qml.py` generates the QML singletons; `tools/gen_settings.py` checks `settings/schema.json` and
generates `shell/services/SettingsSchema.js` from it; `tools/gen_sources.py` generates
`shell/widgethost/SourceCatalog.js` from `widgets/sources.json` (the widget data sources, D79) and `shell/widgethost/SpecSchema.js` from `widgets/spec.schema.json` (the shell's widget check, D85); `tools/gen_kvantum.py` generates the Kvantum theme templates
(`theme/apps/kvantum.svg`, `.kvconfig`, D60);
`tools/palette.py` renders and validates `palette.json` for development (the shell does its own, D53); `tools/qtws.py` builds the Qt workspace and runs
tests, lint, GPU tests and gallery renders, the Quickshell tests (`test-qs`) and the real shell under a headless
sway (`test-wayland`); `tools/fontconf.py` writes the dev shell's fontconfig;
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
| `RUTILE_MATUGEN` | tests, `shell/services/WallpaperService.qml` | matugen binary when it is not on `PATH`; the shell's tests point it at a stand-in |
| `RUTILE_FONT_DIRS` | tests, `tools/fontconf.py`, flake | font directories; the font tests run only if they find the real files |
| `RUTILE_OPENCODE` | tests | opencode binary for the real-config checks |
| `RUTILE_OPENCODE_STALL` | tests | seconds without a model request before a real-opencode run counts as hung (default 20) |
| `RUTILE_ANIMATION_SPEED` | `shell/shell.qml` | overrides the `motion.speed` setting for this run (D43): 1 normal, 2 twice as fast, 0 no motion; `ipc call motion setSpeed 2` saves a new speed |
| `XDG_CONFIG_HOME`, `XDG_STATE_HOME` | `shell/services/Settings.qml` | where `$XDG_CONFIG_HOME/rutile/settings.json`, `managed.json` and `$XDG_STATE_HOME/rutile/state.json` live (D45); the tests point them at temporary directories |
| `RUTILE_PALETTE` | `shell/common/PaletteWatcher.qml` | `palette.json` path, default `~/.cache/rutile/palette.json` |
| `RUTILE_PAM_DIR`, `RUTILE_PAM_CONFIG` | `shell/lock/LockScreen.qml` | tests only: the PAM directory and service the lock screen uses instead of `/etc/pam.d` and `login` |
| `RUTILE_PYWALFOX_POLL` | `native/pywalfox-host.c` | seconds between checks of the Firefox colors file (0.01 to 60, default 1; tests use less) |
| `RUTILE_PYWALFOX_HOST` | `shell/services/AppColorsService.qml` | the compiled Firefox host when it is not `build/rutile-pywalfox-host` (a package; tests point it at a stand-in) |
| `RUTILE_SHELL_QML` | `bin/rutile-shell` | the shell to run and call (the package sets it; a checkout uses `../shell/shell.qml`) |
| `RUTILE_CLI` | `bin/rutile-shell`, `shell/settingsapp/SettingsWindow.qml` | the `rutile-shell` command itself, which Settings starts for Flatpak apps (D66); the package sets its wrapper, a checkout the script's path |
| `RUTILE_QUICKSHELL` | `bin/rutile-shell` | the quickshell binary, default `quickshell` on PATH (tests point it at a stand-in) |
| `RUTILE_PLAIN_GTK4` | `tools/dev/theming_check.py` | `0`: check with `programs.rutile.theming.gtk.plainGtk4` off (plain GTK 4 apps not expected to match) |
| `RUTILE_AMDGPU_IDS`, `RUTILE_PCI_IDS` | `shell/widgethost/sources/GpuSource.qml` | libdrm's amdgpu.ids and hwdata's pci.ids, for graphics card names (the package sets both; without them, /usr/share's) |
| `RUTILE_WEATHER_URL` | `shell/widgethost/sources/WeatherSource.qml` | the weather address instead of Open-Meteo's (tests point it at a local server) |
| `RUTILE_CALENDAR` | `shell/calendar/EdsCalendar.qml` | the evolution-data-server reader when it is not `build/rutile-calendar` beside the shell (D95; tests point it at a stand-in) |
| `RUTILE_CALENDAR_APP` | `shell/calendar/CalendarWindow.qml`, `shell/settingsapp/SettingsWindow.qml` | the calendar app instead of `gnome-calendar` (tests: a stand-in) |
| `FAKE_CALENDAR_LOG`, `FAKE_CALENDAR_EVENTS` | `tests/qs/bin/fake-rutile-calendar` | tests only: where the stand-in logs its calls, and the events it prints |
| `RUTILE_TEST_PORT` | `tests/qs/tst_widget_sources_live.qml` | tests only: the free local port of the test's own web server (`@PORT@` in a test's `// env` lines) |
| `RUTILE_PAPIRUS` | `shell/services/Files.js` (folder icons, D64) | Papirus-Dark's folder when it is not in `XDG_DATA_DIRS` (tests) |
| `RUTILE_SANDBOX` | `tools/dev/setup_sandbox.sh` | where the setup script downloads to |
| `OLLAMA_HOST` | `tools/sidework.py` | Ollama address, default `127.0.0.1:11434` |
| `OPENCODE_CONFIG_CONTENT` | set by `tools/sidework.py agent` | inline opencode config, merged after any project file |

## 8. Resume prompt for a new chat

Point it at https://github.com/randalthor17/rutile (or upload the latest bundle) and say:

> This is the Rutile Shell project. Read `docs/HANDOFF.md`, then `docs/PLAN.md`, and continue from "Next up".
> Follow the working agreement in the handoff. Update the plan, changelog and your memory as you go.

A different AI or person can use the same instruction. Everything needed is in the repo.

## 9. Open questions for the maintainer

- How does the shell look and feel in the real session, next to the Googlebook references? (Ripple, shadows and the
  focus ring are deliberately not done yet.)
- Does GNOME Calendar open the clicked event (`--uuid <calendar>:<event>`, D95), and how soon do Google edits show?
- Plan item 0.2: Googlebook screenshots of Quick Settings, the launcher and Settings are still missing; GeminiGlow
  needs one too.
- Plan item 1.1b: default seed color and scheme type, chosen against the references.
- When widget generation returns (D82): is the local-model line worth keeping, and on which tier?
