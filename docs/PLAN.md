# Plan and progress

The canonical checklist for Rutile Shell. Memory keeps a copy; **this file wins** if they differ. Every line is
`- [ ]` (open) or `- [x]` (done) with a stable bold id. Update it in the same commit that changes the state, and
note the release (or "unreleased") for finished items. Ids are never reused. `tests/test_handoff.py` checks the
format and that ids are unique.

Rules that apply to every item are in `docs/HANDOFF.md` (working agreement). Why things are decided as they
are: `docs/DECISIONS.md`. Gate for every phase: the maintainer signs off after looking at it.

## Phase 0: decisions and references

- [x] **0.1** Name Rutile Shell, MIT license.
- [ ] **0.2** Collect references in `docs/reference/`: the four supplied Googlebook images, the DMS and Noctalia
  screenshots (received: quick settings, launcher, settings). Googlebook Quick Settings (with edit mode),
  Settings and the desktop are in, with notes per part in `docs/reference/README.md` (unreleased). Still
  missing: the Googlebook launcher.
- [x] **0.3** M3E values into tokens JSON (v0.1.0): `tools/gen_tokens.py` parses vendored androidx Compose
  Material3 sources, sha256-pinned: shape corners, springs, durations, easings, elevation, type scale.
- [x] **0.4** Monorepo with git, `make check`, MIT `LICENSE`, `NOTICE` (v0.1.0).

## Phase 1: theme, tokens, M3E kit (gate: gallery sign-off)

- [x] **1.1** matugen config and template emitting `palette.json`, 49 roles, both modes per file (v0.2.0).
- [ ] **1.1b** Decided: stay on matugen (2021-spec palette) for now; swap in an own generator
  (materialyoucolor-based, 2025 spec, or Noctalia's) behind the same `palette.json` only if matugen does not look
  as good. Open: the default seed color and scheme type, chosen against the Googlebook references.
  Quickshell's `ColorQuantizer` gives a wallpaper's dominant colors (a seed), not a scheme.
- [x] **1.2** Palette tests, cross-checked against materialyoucolor: matugen matches the 2021 spec 94.7%, not the
  2025 spec (v0.2.0).
- [x] **1.3** QML singletons: generated Colors, Shapes, Motion, Type, Elevation; Spacing, Spring (exact M3 spring
  solver), PaletteWatcher (v0.3.0). Color roles `on_x` are `xOn`.
- [x] **1.3b** Nix dev shell and Qt module-path handling in `tools/qtws.py` (v0.3.1).
- [x] **1.4** Fonts (v0.4.0): Google Sans Flex through the maintainer's own nix package, Material Symbols Rounded
  from nixpkgs; `theme/fonts.json` is the single source; `Fonts.qml` and `Type.font()` generated.
- [x] **1.5a** First components (v0.5.0, fixed in v0.5.1): Surface, StateLayer, Icon, Button (5 types x 5 sizes),
  IconButton, SpringColor, specs from the Compose tokens (XS button corrected per `Button.kt`), and the gallery.
  The gallery opens in real Quickshell. Not done: ripple, elevation shadow, focus ring.
- [x] **1.5b** Filled-icon glitch fixed (unreleased): `Icon` uses `Text.NativeRendering`; GPU-path regression
  test in `tests/qml_gpu/` (`make check-gpu`).
- [x] **1.5c** Switch, Slider, ProgressBar (unreleased): specs from the vendored Compose token files plus the few
  values Compose hardcodes (parsed from `Slider.kt`, `ProgressIndicator.kt`, `WavyProgressIndicator.kt`), in the
  gallery. Slider is horizontal; ProgressBar is linear and determinate (flat or wavy). Not done: vertical and
  range sliders, the slider value label, indeterminate and circular progress.
- [x] **1.5d** Tile, Chip, ListItem (unreleased): Tile after Android 16 SystemUI (D32), Chip (assist, filter) and
  the expressive segmented ListItem from the Compose tokens; in the gallery. Not done: input and suggestion
  chips, three-line and avatar/image list items, the tile focus border. The Googlebook references show the
  same tile (D32). Switch, Tile and filter Chip have a `controlled` mode: they change only when the applied
  setting does (D33, unreleased).
- [x] **1.5e** Expressive slider sizes and track icons (unreleased, D36): `size` xs, s, m, l, xl from Material
  Components Android's tokens, `startIcon`/`endIcon` inside the track on m and up (the end icon moves beside the
  handle near full, as in Android 17), corners that shrink on a short part, right to left. In the gallery as Quick Settings' brightness and volume rows. Not done: vertical, range,
  centered, the value label, the other two icon slots.
- [x] **1.5f** ShapeMorph (unreleased, D37): the 35 shapes of Compose's `MaterialShapes` and morphing between
  them, ported from androidx graphics-shapes and checked against an independent Python port; in the gallery.
  Not done: a picture clipped to a shape, rotation while morphing, outlines.
- [ ] **1.5** Component kit, remaining: FAB, Card, TextField, Menu, Dialog, NavRail, GeminiGlow gradient border,
  and the 1.5c leftovers when something needs them. Likely next: GeminiGlow, or what Quick Settings (2.6) needs
  first (the slider is done, 1.5e).
- [x] **1.6** Shared EditableGrid, ported from DMS `DEditableGrid` and `GridLayout.js` packing: drag and swap,
  sizes clamped to columns/rows, edit mode; used by both Quick Settings tiles and the desktop widget grid
  (unreleased). Select, drag with a placeholder, a resize handle on every side that can move, neighbors that
  shrink before they move (D34), `maxRows`, gravity that leaves no gaps (D35), right to left, commits through the
  owner; in the gallery as
  Googlebook's "Edit tiles". Not done: keyboard editing, drag in from outside.
- [ ] **1.7** Gallery covering every component, compared against the spec and screenshots. Exists for the current
  components; extend as each lands. The maintainer's look review is pending.

## Phase 2: shell core (on niri)

- [ ] **2.1** Started: `shell/services/` wraps Pipewire (volume, mute, mic), Networking (Wi-Fi), Bluetooth and,
  through brightnessctl (D39), the backlight; enough for Quick Settings. Next: UPower, Mpris, notifications, tray.
  Quickshell built-in services first (Pipewire, UPower, NetworkManager, Bluetooth, notifications,
  MPRIS, tray); a small daemon only for real gaps (settings persistence, widget validation, Ollama bridge).
  Types: `Pipewire`, `UPower`/`PowerProfiles`, `Networking`, `Bluetooth`, `NotificationServer`, `Mpris`,
  `SystemTray` (the table in `docs/HANDOFF.md`, "Quickshell types and where they go").
- [ ] **2.2** niri integration: IPC (workspaces, windows, focus events); the shell ships a generated niri config
  module (window rules, keybinds, startup). Waiting (D38) for Quickshell's `Quickshell.Niri` module
  (quickshell-mirror/quickshell PR #949, open in October 2026); not `Quickshell.WindowManager`. If it has not
  merged when this item starts: pin the PR commit as a flake input (maintainer's approval) or a small `Socket`
  client on `$NIRI_SOCKET`, behind a thin `Niri` singleton either way. `IpcHandler` for keybinds into the shell.
- [ ] **2.3** Started: the status pill at the top right of every screen (network, volume, battery; opens Quick
  Settings, D41; scrolling over the volume glyph changes the volume). Desktop surface: wallpaper layer, right-aligned desktop icon grid (tonal circles with labels),
  floating time/date top-left, status icons top-right, no top bar. Types: `PanelWindow` on `WlrLayer.Background`,
  `Variants` over `Quickshell.screens`, `SystemClock`, `Mpris`, `IconImage`.
- [ ] **2.4** Shelf: bottom layer-shell bar, "G" pill launcher, pinned apps from config, running-app indicators
  via niri IPC, divider, special buttons, M3E hover and press motion. Types: `PanelWindow` (bottom,
  `ExclusionMode`), `DesktopEntries`, `IconImage`, `ToplevelManager`, `LazyLoader` for its popups.
- [ ] **2.5** Settings registry and search: declarative registry like DMS `SettingsTabs` (id, text, icon, hint,
  aliases, children, advanced/hidden flags), JSON-schema-backed config store, settings search service.
- [ ] **2.6a** Done (unreleased, D40): `shell/shell.qml` runs Quick Settings in a layer-shell window created only
  while open, toggled with `quickshell -p shell/shell.qml ipc call quicksettings toggle`: header, brightness and
  volume, Wi-Fi, Bluetooth, Microphone, Dark theme and Airplane mode tiles, edit mode (remove, rearrange, resize).
  Tested offscreen with a fake backend and as the real shell under a headless sway. Since then: opens from the
  status pill on its screen, closes when focus leaves (D41), `ipc call quicksettings state`. Not done: see
  `docs/quick-settings.md`.
- [ ] **2.6** Status tray and Quick Settings on the shared EditableGrid: tiles as saved data (id + size),
  per-tile detail pages, Add Widget sheet, sliders. Types: `PopupWindow` or `PanelWindow` in a `LazyLoader`,
  the 2.1 services, `SystemTray` with `QsMenuOpener`.
- [ ] **2.7** Launcher: search field, category chips, grid/list toggle; DMS `Scorer.js` ported (weighted fuzzy,
  frecency, type bonuses); smaller controller with apps and settings providers first. Types: `DesktopEntries`,
  `IconImage`, `LazyLoader`.
- [ ] **2.8** Notifications, toasts, OSD, lock screen (PAM). Types: `NotificationServer`, `WlSessionLock`,
  `PamContext`, `IdleMonitor`, `PolkitAgent`.

## Phase 3: windows on niri

- [ ] **3.1** Googlebook-like floating windows via niri window rules (default floating, corner radius, shadow,
  focus ring); our own apps draw M3E title bars with ChromeOS-style caption buttons; third-party apps get GTK/Qt
  theming and rules (niri draws no title bars). Our own surfaces can blur with Quickshell's `BackgroundEffect`
  (niri supports `ext-background-effect-v1`, D38); third-party windows get none.

## Phase 4: widget system (the core feature)

- [x] **4.1** Widget spec v1 (JSON, versioned) with primitives card, header, tile, hero image, stat, progress,
  list row, chip, row/column/grid, and a JSON Schema (unreleased). The local model's draft was merged as a known
  failing draft and Claude rewrote the schema on main (recursive `$defs`, surface-role `tone` enum, unknown
  fields rejected at every level); its five examples pass `tools/widget_check.py` and `jsonschema`, and
  `tests/test_widget_spec.py` pins what the spec refuses. Node fields are a first cut: the renderer (4.3) may refine them.
- [ ] **4.2** Data sources: clock, weather (keyless API), calendar, battery, system stats, countdown, HTTP JSON
  (allowlisted), files; bindings `{{source.field}}` with no arbitrary JS. Types: `SystemClock`, `UPower`,
  `Mpris`, `FileView`, `Process`.
- [ ] **4.3** WidgetHost renderer: builds QML from the spec with Loader/Repeater.
- [ ] **4.4** Desktop widget grid reusing the EditableGrid (1.6): snap, edit mode, persistence.
- [ ] **4.5** Custom widgets app: category list and template cards (weather, daily update, world clock, finance,
  countdown, sports) plus a "Create a widget" prompt box. Templates are local-model task `widget-templates`.
- [ ] **4.6** CLI: widget check / preview / install with machine-readable errors. Started: `tools/widget_check.py`
  checks a schema against the spec's rules and widgets against the schema (stdlib JSON Schema subset).
- [ ] **4.7** Ollama bridge: structured output with the schema as format, system prompt from the LLM docs, retry
  loop feeding validator errors back, model configurable (Ollama Cloud now, local on the 9060 XT later).
- [ ] **4.8** Docs for LLMs: one file with catalog, tokens, data sources, rules and 8+ worked examples, plus the
  schema and `llms.txt`. First part is local-model task `llm-docs`.
- [ ] **4.9** Eval set of about 30 widget prompts; target at least 90% valid widgets within 3 retries on a model
  that fits 16 GB.
- [ ] **4.10** (later) QML escape-hatch widgets with a tiny base class.

## Phase 5: settings app UI

- [ ] **5.1** Separate window with M3E sidebar, hub pages and lazy-loaded page files on the registry from 2.5,
  an advanced toggle and global search.
- [ ] **5.2** Pages: Network, Bluetooth, Display (niri outputs), Sound, Wallpaper and style (seed color, scheme),
  Widgets, Shelf, Apps, Power, Input, About.

## Phase 6: NixOS distro (the v1 goal)

- [ ] **6.1** NixOS flake modules for niri config, shell, settings, widgets, matugen, fonts; home-manager
  integration; default config.
- [ ] **6.2** Custom greetd greeter in the same style. Types: `Greetd`.
- [ ] **6.3** Installer ISO.

## Phase 7: QA for v1

- [ ] **7.1** Visual comparison pass against the references per screen; performance budget; docs complete.

## Later versions

- [ ] **L1** v2: KDE Connect (Quick Access, notification mirroring).
- [ ] **L2** v4/v5: Magic Pointer (wiggle detection, portal screen capture, vision model, prompt pill with
  GeminiGlow), Cast My Apps, optional software Glowbar.
- [ ] **L3** Far future: COPR packages, PKGBUILDs, possibly Universal Blue distros.

## Side work with a local model

- [x] **S1** Tooling (unreleased): `tools/sidework.py`, commit-time guard, flake `local-ai` shell and NixOS module,
  `docs/sidework.md`, conventions and three task briefs. Switched from aider to opencode after the maintainer
  found aider's workflow unusable for agentic work. Moved to opencode 2.x (unreleased): config rewritten
  against the real 2.1.1 schema, `--standalone`, `PWD`, `execute` removed, tested end to end with a scripted model.
  Cleanup in one step: `merge TASK --close`, `close --merged`.
- [ ] **S2** Trial: run one bounded task on the 9060 XT (suggested `widget-schema`) and judge speed, tool-calling
  reliability and output quality. Also confirm ROCm works on the card (`ollama ps` shows 100% GPU).
  First attempt (2026-10-25, qwen3:14b, `local/widget-schema`): the model worked but could not check its output
  and fails the brief (schema not recursive, no `tone` enum, examples rejected). Merged with
  `sidework.py merge --accept-failing` (092d213, the TODO is in the commit) and fixed by Claude (see 4.1). The
  tooling it lacked is now in place, and the acceptance check gates every commit and merge (D30), so this
  cannot recur silently. Still to judge: speed and ROCm, on the next task (`llm-docs` or `widget-templates`).
- [ ] **S3** Tasks done and merged: `widget-schema` (done, as a draft fixed by Claude), `llm-docs`, then
  `widget-templates` (now unblocked). Each ends with `sidework.py check --run-checks`, `merge-check`, and a Claude review plus tests.

## Handoff and housekeeping

- [x] **H1** Handoff docs (unreleased): `docs/HANDOFF.md`, this plan, `docs/DECISIONS.md`, `docs/LESSONS.md`,
  `CHANGELOG.md`, `AGENTS.md`, and reproducible dev tools in `tools/dev/`.
- [ ] **H2** Standing rule: keep this file, `CHANGELOG.md` and memory in step with every change.
- [ ] **H5** Standing rule: Quickshell first. Check the Quickshell docs for the installed version before building
  and use its types where they fit (the table in `docs/HANDOFF.md`). Done so far: `tools/qtws.py test-qs` runs
  tests that need Quickshell (tests/qs/) as shells under `quickshell`, offscreen, in `make check`;
  `PaletteWatcher` is now tested (load, reload on change, missing file). Nothing in the components needed
  migrating: Quickshell has no controls, and their `Loader`s are small in-item parts, not windows.
- [ ] **H4** Standing rule (D31): light on memory. Lazy-load everything not on screen, measure new components
  with `tools/dev/memcost.py`, follow `docs/memory.md`. First pass done: components 26-64% smaller.
- [ ] **H3** First `nix develop` on the maintainer's machine writes `flake.lock`; commit it.

## Decisions waiting for the maintainer

- Next component batch (1.5), see "Next up" in the handoff.
- Default seed color and scheme (1.1b).
- Ripple, elevation shadows, focus ring: build, or leave as the flat look? Decide from the gallery.
- Whether to start the local-model trial (S2).
