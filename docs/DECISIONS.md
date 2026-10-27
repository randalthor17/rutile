# Decisions

Why things are the way they are. Each entry: the decision, the reason, what was rejected, and what would
justify revisiting it. Add an entry when you decide something non-obvious; do not rewrite history, supersede
an entry by adding a new one that says so.

## Product and scope

**D1. Name Rutile Shell, MIT license.** Chosen by the maintainer. MIT lets us port logic from DankMaterialShell
and Noctalia (both MIT) with attribution. Caelestia is GPL-3.0, so it is read-only reference: copying any of it
would force GPL on this repository. Revisit: never without a licensing reason.

**D2. Fidelity target is the Googlebook UI, built on the M3 Expressive spec.** The Googlebook UI conforms to
M3E, so values come from the spec's tokens, not pixel measurement. Only the Google-specific layer (shelf, glow
border, Magic Pointer, Glowbar) is matched by eye from the screenshots and poster.

**D3. Roadmap.** v1 is shell, widgets and settings on NixOS. v2 adds KDE Connect (Quick Access). Magic Pointer and
Cast My Apps are v4 or v5 (wiggle detection is hard on Wayland; Cast My Apps is a separate project). COPR,
PKGBUILD and Universal Blue are far future.

## Platform

**D4. niri is the compositor; no KWin.** KWin has real window-decoration plugins but too many dependencies, per
the maintainer. niri supports floating windows and window rules (corner radius, `open-floating`, clipping) and an
IPC event stream the shelf can use for running apps. Consequences: niri draws no title bars, so our own apps
(Settings, Custom widgets) draw M3E title bars with ChromeOS-style caption buttons; third-party apps get
rounded corners and shadows from rules but not caption buttons; upstream niri has no blur, so v1 uses solid
tinted surfaces.

**D5. Quickshell/QML, our own shell, not a fork.** Noctalia v5 is a C++ rewrite with Luau plugins, so it is not a
base. Forking inherits someone else's look, and the look is the goal. We reuse structure and logic: DMS for the
settings registry, quick-settings tiles and launcher scorer; Caelestia only as a reading reference for M3E
component structure.

**D6. NixOS flakes first.** `flake.nix` provides the dev shells, the font package and a NixOS module. Distribution
packaging comes after v1 works.

## Design system

**D7. Tokens come from vendored Compose Material3 sources, generated and checksummed.** `tokens/sources/` holds
the Kotlin files, `manifest.json` pins sha256, and `tools/gen_tokens.py` / `tools/gen_components.py` fail loudly
on anything they do not recognize. They are not scraped from m3.material.io. Revisit if the spec pages become
machine-readable or Compose diverges from the spec.

**D8. The XS button correction.** `ButtonXSmallTokens.kt` is stale upstream (Compose overrides it in code with 12 px
padding and a 4 px icon gap and has TODOs saying so). The generator applies that override, records it in
`tokens/components.json`, and fails if the TODOs disappear so a fix upstream forces a review.

**D9. Palette from matugen 4.2.0 for now.** Measured against materialyoucolor: matugen agrees 94.7% with the
2021-era color spec and about 60% with the 2025 spec that M3E uses, and lacks the `*_dim` roles. Accepted because
matugen also themes other apps and fits the Nix setup. `palette.json` (format 1) is the stable interface, so a
2025-spec generator (materialyoucolor-based, or Noctalia's) can be swapped in behind it. Revisit when the
palette looks wrong next to the Googlebook references (plan item 1.1b).

**D10. Springs are solved exactly, not through Qt's `SpringAnimation`.** Qt's parameters are not M3's stiffness and
damping ratio. `SpringMath.js` solves the damped spring analytically (mass 1, the Compose model), checked against
an independent Python version that is itself checked against numerical integration. Spatial springs (shape,
position) overshoot slightly; effects springs (color, opacity) never do. Effects springs are critically damped, so
since D31 they run as Qt animations on the equivalent curve (`EffectsColor`, `EffectsNumber`, fitted in
`tools/gen_qml.py`); `Spring` stays for spatial motion.

**D11. Color roles `on_x` are exposed as `xOn`.** QML reads any property named `on` plus a capital as a signal
handler, so `Colors.onPrimary` silently returned nothing. The generator refuses such names.

**D12. Fonts.** Text is Google Sans Flex 4.007 through the maintainer's own nix package (`nix/googlesans-flex.nix`,
OFL-1.1, not in nixpkgs, vendored verbatim, hash verified). Icons are Material Symbols Rounded from nixpkgs.
`theme/fonts.json` is the single source for family names and axes; tests check the real files against it. Fonts
are not vendored in the repository.

**D13. `Icon` uses `Text.NativeRendering`.** Qt's default distance-field text corrupts filled Material Symbols
glyphs (FILL 1): light holes and streaks, reproduced on Qt 6.12 under OpenGL in every state. `CurveRendering`
leaves hairline seams. Cost: possible subpixel color fringes at glyph edges. Revisit if Qt fixes distance-field
handling of overlapping contours (the GPU test in `tests/qml_gpu/` will say).

**D14. `Type.font()` sets `wght` and `opsz` through `font.variableAxes` where Qt has it** (6.7+, feature-detected).
Without it only the named instances are reachable (Regular and Bold render, Medium does not).

**D15. Spacing is Rutile's own 4 px grid.** M3 publishes no spacing tokens.

**D16. Not built yet, on purpose:** ripple (rounded clipping needs masking), elevation shadows (need
`QtQuick.Effects`, Qt 6.5+), the M3E focus ring. Decide from the gallery whether they are wanted.

## Architecture (planned)

**D17. Settings and Quick Settings follow DMS.** A declarative settings registry with search; Quick Settings
tiles are saved data (id and size) on one shared EditableGrid that the desktop widget grid also uses. The
registry moved up to Phase 2 so the launcher can search settings.

**D18. Widgets are a JSON spec, not generated QML.** Small local models write QML badly. A fixed vocabulary of M3E
primitives plus data sources, a JSON Schema, constrained generation with Ollama structured output, a validator
CLI whose errors feed a retry loop, and one LLM-oriented document. QML escape hatch comes later.

**D19. Ollama Cloud for LLM work now; local on the RX 9060 XT (16 GB) later.** The bridge takes a configurable endpoint.

## Process and tooling

**D20. Test infrastructure mirrors Quickshell.** `tools/qtws.py` builds a workspace whose `qs.common`,
`qs.components` and `qs.gallery` modules look like Quickshell's import root. Tests run offscreen with the
software renderer. Tests that need something optional (matugen, real fonts, Qt tools, a display, opencode)
skip with a printed reason. GPU-path tests are separate (`make check-gpu`).

**D21. Mutation testing is part of "tested".** Break the code on purpose and confirm the tests fail. This found
several tests that could not fail (an equivalent mutant is recorded as such, not forced).

**D22. Dev shells.** `default` is light; `local-ai` (x86_64 only, ROCm does not exist elsewhere) carries Ollama and
opencode, a multi-gigabyte closure the everyday shell must not pull in. The NixOS module is separate.

**D23. Release protocol.** Tag-worthy commits get a version tag and a bundle. Untagged commits ship as
`rutile-dev-<sha>.bundle`. Delivered tags are never moved.

## Local-model side work

**D24. Conflicts are made impossible, not unlikely.** Disjoint ownership (`tools/ownership.json`), a worktree and
branch per task, and a pre-commit hook installed from the main checkout (absolute `core.hooksPath`) that reads the
main checkout's rules, so editing `tools/` inside the worktree cannot weaken it. The first design read the rules
from the worktree being policed; that hole was found by testing and fixed. `sidework.py check` is the backstop for
commits made with `--no-verify`.

**D25. opencode, not aider.** aider's edit-format workflow did not work for agentic coding with a local model
(maintainer's experience). opencode is a real agent loop. Its tool-level permissions are a first layer only: the
agent has a bash tool, so this is not a sandbox; the commit guard and `check` are the boundary.

**D26. The agent's config is passed inline in `OPENCODE_CONFIG_CONTENT`, for opencode 2.x.** The maintainer moved
to 2.x (commit c62dbf8); the launcher now refuses 1.x. 2.x merges the inline config after a project `opencode.json`
and evaluates permission rules as an ordered list, last match wins; every restricted action starts with our
catch-all, so a hostile project file cannot widen anything (verified end to end with the real 2.1.1). The launcher
runs `--standalone` (a background service would never see the inline config) and sets `PWD` to the worktree
(opencode follows `$PWD`). `execute` is removed: it can `fetch` and create worktrees without asking. Shell commands
can still write anywhere, so the guard stays the boundary.

**D27. Qwen3 family, 32K context baked into a derived model.** An agent needs reliable tool calling and a long
context. Ollama defaults to 4096 tokens and its OpenAI-compatible endpoint ignores a per-request context, so
`sidework.py prepare` creates `rutile-<tier>:32k`. `qwen2.5-coder` is not used: reported to hang in opencode's tool
loop. Tiers: `qwen3:14b` (default, fits 16 GB), `qwen3:8b`, `qwen3-coder:30b` (does not fit, partly CPU). Tags and
sizes come from third-party summaries and are unverified on the maintainer's hardware.

**D28. Model entries declare `capabilities.tools` and the provider names its `package`.** 1.x silently sent no tools
without `tool_call`; 2.1.1 sends them regardless, but the declaration is kept. Without
`"package": "@ai-sdk/openai-compatible"` 2.x refuses the model outright.

**D29. Local tasks ship with a check the model can run, using only the standard library.** The first trial model
spent most of its session trying to install `jsonschema` (venv, flake edits) because its brief named no runnable
check. `tools/widget_check.py` implements the JSON Schema subset a widget spec needs and refuses every other
keyword, so a schema cannot depend on a rule nothing enforces; it is cross-checked against `jsonschema` when that
is installed. It belongs to the main line; the model runs it but may not edit it.

**D30. A task's acceptance check gates commits and merges, not just reviews.** Prose acceptance criteria let the
first trial commit a schema that rejected its own examples. Each brief now declares one command; the commit hook
runs it on the staged work, `check` and `merge` run it on the would-be merge result, all using the main
checkout's brief and tools. A known-broken branch can still be merged deliberately (`--accept-failing`, reason
recorded in the merge commit), so the gate never forces work to be thrown away.

**D31. The shell is light on memory, and Qt 6.7 is the minimum.** The maintainer's standing requirement: the
shell runs all day, so everything not on screen is created on demand and unloaded when closed, components keep
optional parts behind Loaders, colors and opacities animate with Qt's C++ animations on the property (a
JavaScript spring object per color cost three times as much), Rectangles replace Canvas wherever they can draw
the shape, and nothing animates while idle. Rules and measurements are in `docs/memory.md`; the lint enforces
the mechanical ones and `tools/dev/memcost.py` measures the rest. Qt 6.4 was only ever the sandbox's Qt: the
flake's Quickshell 0.3.2 is built on Qt 6.12, so the code now uses Qt 6.7 features (per-corner radii,
`font.variableAxes` without feature detection, `pragma ComponentBehavior`) and tests run on 6.12.

**D32. The Quick Settings tile follows Android 16 until Googlebook references exist.** Material has no tile
component, and the Googlebook screenshots are not in the repository yet (plan 0.2). The maintainer chose
Android 16's SystemUI tile as the stand-in: its sizes, corner radii and per-state colors are parsed from the
vendored `Tile.kt` and `CommonTile.kt` (Apache-2.0), like the Compose token files. Revisit against the
references when they arrive. Revisited (2026-10-26): the Googlebook Quick Settings screenshots show Android 16's
tile unchanged (pill when off, rounded square when on, the dual-target icon box, 4 columns with large tiles
spanning 2), so the stand-in stays as it is (`docs/reference/README.md`).

**D33. A toggle shows the state the system is in, not the one asked for.** The maintainer's rule: a tile,
switch or chip wired to a setting turns on or off only once the setting has applied, and follows it when it
changes elsewhere. The controls have a `controlled` mode: a click emits `toggled(wanted)` and changes nothing;
the owner binds the state to the backend's. Assigning the state inside the control would also break that
binding, so the uncontrolled default is for demos only.

**D34. Grid items resize from any side, and neighbors shrink before they move.** The maintainer's rules for
Quick Settings edit mode: every tile can grow to the full width and in height, a handle shows on each side
that can actually move, and a neighbor in the way gives up cells down to its minimum size before it is pushed
elsewhere. Googlebook shows only a right-edge handle and two tile widths; this goes further on purpose. Right to
left follows Qt's `LayoutMirroring`, set once at the shell's root from the locale: the grid reads it for its
columns and the Tile lays out with anchors, so neither needs its own setting.

**D35. A Quick Settings grid keeps no gaps, and nothing stretches to fill one.** The maintainer's rule: no empty
space at the top, at the start of a row or between tiles. The maintainer chose "slide forward" over growing a
neighbor into the gap: with `gravity` on, tiles keep their reading order and each takes the first free cell
after the tile before it, wrapping to the next row when it does not fit, so free space is left only at the end
of a row and the last tile never stretches into it. DMS's gravity only pulled items up, which can let a later
tile jump ahead into a hole; the flow keeps the order. Items without a saved position join at the end, and the
"is there room" check for adding one uses the same flow. The full behavior is in `docs/editable-grid.md`.

**D36. The expressive slider sizes come from Material Components Android's tokens.** Quick Settings needs the
40 px slider with an icon in its track (Googlebook, `docs/reference/README.md`). Compose has no tokens for the
five expressive slider sizes yet; Material Components for Android (Apache-2.0) does, generated from the same
token sets (`md.comp.slider.xsmall` .. `xlarge`). Its `tokens.xml` and `dimens.xml` are vendored next to the
Compose files and checksummed the same way, and the generator fails if their xsmall size stops matching
Compose's default slider. From them: track height, outer corner, handle height and icon size per size, the 10 px
icon padding, and the icon colors (the colors MDC uses for what sits on each part of the track). From Compose's
`Slider.kt`: the larger sizes shrink their corners on a short part instead of hiding it, but stepped sliders do
not. The end icon replacing the stop dot is from the Googlebook screenshots, which show no dot beside it.
Near full, the end icon moves to the end of the active part instead of hiding, as Android 17's brightness slider
does (maintainer's reference, `docs/reference/android-17-slider-almost-full.png`); MDC would hide it.

**D37. Shapes come from Compose's `MaterialShapes`, built at run time and drawn with QtQuick.Shapes.** The M3
Expressive shape library (Googlebook's "Up next" widget clips its picture to a cookie) is 35 shapes, each a few
vertices with roundings, repeated and mirrored, then rounded, normalized and morphed by androidx graphics-shapes.
`MaterialShapes.kt` and the graphics-shapes files are vendored and checksummed; the generator parses the shape
definitions (and fails on any construct it does not know), and `ShapeMath.js` ports the algorithms. Rejected:
precomputing every shape's curves into the generated file (about 150 KB of JavaScript held by every user, D31);
the definitions are 5 KB and a shape is built in well under a millisecond when needed. Drawing: QtQuick.Shapes'
curve renderer (Qt 6.7) costs 47 KiB for a circle, 115 for a cookie and 418 for the spikiest shape, the same at
any size; an SVG image rasterized per change was measured at 54 to 103, 93 and 193 (a cookie at 160 px), needs
the qtsvg plugin and the screen's pixel ratio, and blurs when scaled. The geometry renderer is lighter (77 for a
cookie) but not antialiased. Revisit if many shapes end up on screen at once (then the image path), or if Qt
gains a lighter antialiased path renderer.

**D38. niri IPC waits for Quickshell's niri module; our own surfaces may blur.** Supersedes D4's "upstream niri
has no blur, so v1 uses solid tinted surfaces" (per the maintainer, October 2026). Blur: niri supports
`ext-background-effect-v1`, so Quickshell's `BackgroundEffect` can blur behind the shell's own surfaces (panels,
Quick Settings, shelf); third-party windows still get none. niri IPC: `Quickshell.WindowManager` only speaks
ext-workspace-v1, which is not mature, and niri's implementation of it is basic. Quickshell PR #949
(quickshell-mirror/quickshell, "niri/ipc: add niri IPC module") adds `Quickshell.Niri` on niri's own IPC socket:
workspaces, windows, monitors, overview, keyboard layouts, actions, events. It is open and actively developed, so
plan 2.2 waits for it rather than building Quickshell from git (an unreviewed, force-pushed branch to keep
building against nixpkgs' Qt) or writing our own client now. Known limit: niri windows cannot be matched to
Wayland toplevels (niri exposes no window ids over Wayland), so the shelf takes running apps from niri's window
list. If 2.2 starts before it merges: pin the PR commit as a flake input (with the maintainer's approval) or a
small `Socket` client on `$NIRI_SOCKET`, behind a thin `Niri` singleton so switching later touches one file.
Revisit when #949 merges or stalls.

**D39. Backlight brightness through brightnessctl.** Quickshell has no brightness service. brightnessctl writes
through systemd-logind, so it needs no root, udev rule or setuid wrapper on NixOS: installing the package is
enough (NixOS wiki). It finds the backlight device, reports it in one machine-readable line and is small and
maintained. Rejected: our own sysfs reader plus logind's `SetBrightness` over `busctl` (no package, but more code
of our own for the same thing); ddcutil and ddcci-driver for external monitors (permissions or an out-of-tree
kernel module; maintenance for a later, opt-in NixOS option if wanted). Without brightnessctl or a backlight the
brightness slider is hidden. brightnessctl reports no changes, so the panel rereads the level when it opens.
Approved by the maintainer as a runtime dependency (October 2026); in the dev shell, and in the NixOS module (6.1).

**D40. Quick Settings is a panel with a backend interface, in a window that exists only while open.** The panel
(`shell/quicksettings/QuickSettingsPanel.qml`) is plain QtQuick and reaches the system only through a duck-typed
`backend`, so the same file is tested offscreen with a fake and shown in the gallery; the real backend maps
Quickshell's services. The window is a `PanelWindow` in a `LazyLoader`, opened and closed through an
`IpcHandler` (niri keybinds call `quickshell ... ipc call`), and destroyed when closed (D31). Quickshell cannot
create a `PanelWindow` offscreen ("No PanelWindow backend loaded"), so the real shell is tested under a headless
sway (wlroots' headless backend) with a private `XDG_RUNTIME_DIR`: no session compositor, PipeWire or portal is
reachable, and brightnessctl is a fake, so tests cannot change the machine. sway and grim are test-only tools in
the dev shell; the test skips without sway. niri would be the better test compositor, but its headless backend
is internal to its own tests. Revisit if niri gains a headless mode.

**D41. Quick Settings opens from a status pill and closes when it loses keyboard focus.** Googlebook has no top
bar: a pill at the top right shows network, volume and battery and opens the panel below it. The pill is part of
the desktop: layer shell's bottom layer, under windows (the maintainer's choice; the background layer is the
wallpaper's, where stacking is not reliable). The panel is on the top layer. The shell makes one
pill per screen (`Variants` over `Quickshell.screens`) and one backend for pills and panel. To close on an outside
click, the panel closes when its keyboard focus leaves, but only after it had focus (so a compositor that never
gives it focus cannot close it at once). On niri a focusable layer surface gets focus when it opens and loses it
when a window takes focus (checked live). Rejected: a full-screen transparent window behind the panel to catch
clicks, which closes on any click but holds a screen-sized buffer while open (D31), and compositor-specific focus
grabs (Hyprland's). Known gap: a click on empty desktop or on another program's bar does not move focus on niri,
so it does not close the panel; Escape and the pill do. Revisit if that annoys in use. "Focus" here is the
window's (`Window.active`), not an item's `activeFocus`, which moves to a slider or tile inside the panel on a
click (the first version closed the panel when the maintainer pressed the volume slider). sway gives an on-demand
layer surface focus only on a click, so there the panel never had focus and never closes this way.

**D42. The top edge stays visible and windows keep clear of it.** Supersedes D41's layer choice (maintainer,
October 2026: "we don't want 1:1 Googlebook always; keeping the top always visible is our design"). The status
pill is on the top layer, and each screen gets a 1 px transparent, click-through layer surface whose exclusive
zone reserves the pill's margin and height (32 px), so the compositor lays windows out below it and niri's own
gap separates them. This is how DankMaterialShell (`EdgeExclusion.qml`, MIT) and Caelestia (`Exclusions.qml`)
reserve space: the zone does not depend on the surface's size, so the cost is a 1 px buffer per screen instead of
a full-width transparent strip. Rejected: a full-width strip around the pill (screen-wide buffer, and it would
need a click-through mask for its empty part anyway); the bottom layer (windows hid the pill). Gaps between
windows remain niri's setting (`layout { gaps }`), part of the niri config the shell will ship (2.2).

**D43. One motion for every popup, and one speed for every animation.** The maintainer's rule (October 2026):
every dropdown and popup, now and later, opens and closes with the same motion, and every animation (the
chevron, the panel, the slider, all future ones) follows one speed setting kept in one place. Popups use
`PopupMotion` (`shell/components/`): grow from the corner or edge they open from, scale 0.85 to 1 on the default
spatial spring, fade on the effects curve, no input while closing, then `hidden` so the owner unloads; a popup
created on demand uses `PopupLoader`, which keeps it loaded until it has closed. The speed is `Motion.speed`
(generated into `Motion.qml` next to the motion tokens): 1 is Material's speed, 2 twice as fast, 0 no motion.
It is applied in the few places all motion goes through: `Spring.step` scales time (stiffness times speed
squared, same damping, so the shape of the motion is kept), `EffectsNumber`/`EffectsColor` and
`Motion.duration(ms)` divide durations. Outside `shell/common`, a raw Qt animation fails the lint unless its
line says how it applies the speed (`// motion-speed: ...`; ProgressBar's wave and amplitude). The shell reads
`RUTILE_ANIMATION_SPEED` at start and takes `ipc call motion setSpeed <n>`; it moves into the settings store
with plan 2.5. Rejected: per-component speed properties (the speed would drift between components), Qt's
global animation driver rate (does not reach our frame-driven springs).

**D44. The shelf shows windows by workspace, from our own small niri client.** The maintainer (October 2026):
one icon per app hides how many windows there are, and a click that cycles through an app's windows is
guesswork, so the shelf groups the open windows by workspace and shows one icon per window, as Noctalia's taskbar
does (its niri backend was read for the events it handles; no code copied, it is C++). Workspaces are only in
niri's IPC, and Quickshell PR #949 has not merged, so this takes D38's fallback: `NiriService` (a singleton in
`shell/services/`) on Quickshell's `Socket` at `$NIRI_SOCKET`, the event stream folded into plain data by
`NiriState.js`, requests one per connection; no new dependency, and switching to `Quickshell.Niri` later
touches that one file. Pinned apps stay as launchers before the workspaces (a click starts the app); a window's
icon focuses that window (niri's `FocusWindow`). Each screen's shelf shows that output's workspaces that have
windows, the active one tinted, the focused window marked. Without niri the windows come from `ToplevelManager`,
in one group without a number. The wheel over a shelf moves one workspace per notch on that output (niri's
`FocusWorkspace` by id), stopping at the first and at niri's blank last workspace; the active workspace shows
even when empty, so the blank one appears as an empty capsule (maintainer's request). Supersedes the shelf's
per-app running marks from the first shelf commit.

**D45. Settings are JSON in the XDG directories, in layers, and Nix can own any of them.** The maintainer
(October 2026): follow the XDG base directories, and save everything in one format that Quickshell and Nix both
handle, so home-manager modules are easy. That format is JSON: Quickshell reads and writes it with `FileView`,
Nix with `builtins.fromJSON` and `pkgs.formats.json`. TOML and INI were rejected: Nix reads them, but Quickshell
has no reader, so they would need a parser or a daemon. The files:

| Path | Holds | Written by |
|---|---|---|
| `settings/schema.json` (repo) | every setting: type, limits, default, title | us; generated into `shell/services/SettingsSchema.js` |
| `$XDG_CONFIG_HOME/rutile/settings.json` | the user's settings | the shell (settings UI, IPC) |
| `$XDG_CONFIG_HOME/rutile/managed.json` | settings set in Nix | home-manager, read-only |
| `$XDG_STATE_HOME/rutile/state.json` | what the shell remembers: launcher view, usage | the shell, never Nix |
| `$XDG_CACHE_HOME/rutile/palette.json` | the generated palette (already there) | matugen |

A key in `managed.json` beats `settings.json`, which beats the schema's default. A managed key cannot be changed
from the shell (the settings UI will show it as managed by Nix), and the shell never writes `managed.json`. This
is why there are two files: home-manager links its files read-only from the Nix store, so a settings UI writing
to the file Nix owns would fail. State is not configuration: usage counts and the last view do not belong in a
Nix module, so they live apart. The home-manager module (`homeManagerModules.default`, `nix/home-manager.nix`)
builds `programs.rutile.settings` from the same schema, so the shell and Nix cannot drift apart.

The shell keeps every key it does not know when it rewrites `settings.json` (a newer or older shell, a user's
note), so it parses and writes the text itself. Quickshell's `JsonAdapter` was rejected for this: in a probe
with Quickshell 0.3.2 it dropped unknown keys on `writeAdapter()`. A file that does not parse is never
overwritten; the shell keeps the last good values and refuses changes until it is fixed.

**D46. Usage ranks search results only; the grid keeps name order.** Plan 2.7's frecency, after saved state
(D45). Each app opened from the launcher (Open, Enter, a click, or one of its desktop actions) adds one use with
its time to `launcher.usage` in state.json. A use counts fully for four days, then 0.7 to two weeks, 0.5 to a
month, 0.3 to three months, 0.1 after (Firefox's frecency buckets), and the result is the usage count DMS's
scorer already took: up to 2000 points on top of the match, so a used app passes others in its match tier
(prefix, word start, substring) without lifting a typo match over a prefix one. Without a query the grid stays
in name order: positions that move with use are hard to find by memory, and the launcher has no "recent" row
yet. At most 200 apps are kept, so the file stays small. The panel reads the usage once when it opens, so a
launch does not reorder the results under the closing motion. Rejected: ordering the grid by use (the maintainer
can still ask for it; it is one line in `Scorer.rank`), counting launches from the shelf (those are pinned apps
already one click away).

**D47. Notifications: popups under the pill, the list behind a bell, plain text.** The maintainer chose (October
2026): popups at the top right under the status pill, next to where the Googlebook capture has its notification
and do-not-disturb icons, newest on top; the list (history, Clear all, Do not disturb) in its own panel opened
from a bell left of the pill, not in Quick Settings. Built on Quickshell's `NotificationServer`; the service keeps
Quickshell's objects and hands the UI plain data, so the cards test offscreen. Choices made here:

- Body text is shown as plain text: markup is dropped (a `<br>` is a line break) and entities decoded. Senders
  send markup even when the server does not ask for it, and Qt's rich text would load `<img>` sources.
- A popup stays for the sender's timeout, or 6 s when the sender leaves it to us, and not while the pointer is
  over it; critical ones and those asking for 0 stay until dismissed. Quickshell reports the timeout in ms
  (its documentation says seconds). At most three popups show; the rest are in the list.
- A replaced notification (same id) updates in place and does not pop up again: Quickshell does not report a
  replacement as a new notification, and progress updates would otherwise pop up every second.
- Do not disturb is state (state.json), not a setting: it is switched often, and Nix should not pin it.
- Another daemon may own `org.freedesktop.Notifications`; Quickshell then waits and registers when it is
  released (probed), so the shell never takes notifications from a running daemon.
- Tests run the shell on a private session bus (`tools/qtws.py` `PrivateBus`), so a test's server never meets
  the user's session.
- Sounds play through `pw-play` (PipeWire's player, approved by the maintainer; already on a PipeWire system,
  `pkgs.pipewire` in the dev shell) with the Notification media role, not canberra: one process per sound, no
  library in the shell. The sound comes from the sender's `sound-file` or `sound-name` hint, else the freedesktop
  theme's `message-new-instant`, looked up in the XDG data dirs; no theme installed means no sound. Tests put a
  fake `pw-play` first on PATH (tests/qs/bin), so they never make a sound.
- The lock screen (plan 2.8) authenticates with the system's `login` PAM service (Quickshell's default), which
  every distro has, instead of shipping a PAM file of our own. There is no unlock over IPC: anything that can
  call IPC could otherwise unlock. RUTILE_PAM_DIR and RUTILE_PAM_CONFIG point it at another PAM directory, for
  tests only (pam_permit, pam_deny); they give nothing to someone who can already set the shell's environment.
  If the shell dies while locked, niri keeps the screens locked and blank (ext-session-lock); starting the
  shell and locking again brings the lock screen back.
- Lock triggers (plan 2.8): logind's signals come through `dbus-monitor --system` (part of D-Bus, on every system
  that has logind; Quickshell has no system-bus signal type, and `busctl monitor` needs root). The session's Unlock
  signal is ignored, as swaylock does: any program of the user's can send it. Suspend waits for the lock through a
  logind delay inhibitor (`systemd-inhibit ... sleep infinity`, let go once the lock is secure, taken again on
  resume). Idle is Quickshell's IdleMonitor. Test shells get no `XDG_SESSION_ID` (or a fake one with fake
  `dbus-monitor` and `systemd-inhibit`), so they never touch the real session.
- The lock screen's wallpaper is kept decoded small (480x270, about 0.5 MB) while unlocked, so locking shows it at
  once; the full-size image is decoded only while locked (D31).

**D48. The shell draws the wallpaper (plan 2.9).** The maintainer chose this (October 2026) over swaybg, awww or
Noctalia's. The wallpaper feeds the palette and the lock screen, and a Settings picker comes later, so the shell
owning it means one setting drives all three and a change is noticed at once; an outside program would leave the
shell watching its config. Cost: one image decoded at the screen's size per screen (8 MB at 1920x1080), two during
a crossfade. The palette is rendered by running `tools/palette.py` (python3 and matugen, both already needed for
the theme pipeline), found beside the shell directory (`../tools` from `Quickshell.shellDir`); a packaged shell must
ship it there. Video and animated wallpapers stay with outside programs.

**D49. The shell is the session's polkit agent, behind a setting (plan 2.8).** Quickshell's `PolkitAgent` gives
the shell's own password dialog for pkexec, mounts and package installs, in the same style as the lock screen.
Two agents in one session is a muddle: on the maintainer's machine (polkit 127, October 2026) Rutile's registered
after Noctalia's and took the requests from then on. So `polkit.agent: false` is for whoever keeps another agent. The agent's D-Bus object is small and always loaded while the setting is on; the dialog's
window is loaded only while polkit asks (D31). Test shells write `polkit.agent: false` (`tools/qtws.py`
`no_polkit_agent`): polkit is on the system bus, which a test cannot keep private, so a test shell that registered
would take the user's real password prompts. The dialog is plain QtQuick tested with a fake AuthFlow; the real
agent is checked by hand (`pkexec true`).

**D50. The settings app is a window in the shell's process, built from the schema (plan 5.1).** The window is a
Quickshell `FloatingWindow` that the shell creates while it is open and unloads when it is closed (D31), so it
shares the `Settings` service, the palette, the fonts and the components without a second process to keep in
step; a separate `qs` instance would duplicate all of that and talk to the shell over IPC. Rows are made from
`settings/schema.json` (title, description, type, limits), so a new setting needs only a line in the registry
(`shell/settingsapp/Pages.js`) saying which page shows it; how to show it, when the schema alone does not say,
is a hint there too, not in the schema, which stays what the store and Nix need (D45). Choices open a menu for
now; Googlebook's choice dialog comes with the Dialog component (1.5). The "advanced toggle" of the plan became
an Advanced group at the end of a page, which hides nothing behind a global switch. Quickshell cannot raise a
window that is already open, so opening it again only changes its page.

**D51. Files are chosen with the desktop portal's file chooser (plan 5.1).** The maintainer's call (October 2026):
the wallpaper is picked with the portal instead of a picker of our own. `shell.qml` starts with
`//@ pragma Env QT_QPA_PLATFORMTHEME = xdgdesktopportal`, so Qt's FileDialog asks
`org.freedesktop.portal.FileChooser` and the user gets their desktop's chooser (GNOME's or GTK's under niri), with
its previews and recent files, at no cost to the shell. The pragma is read when Quickshell starts (a hot reload
does not apply it) and overrides a `QT_QPA_PLATFORMTHEME` of the user's for the shell only; nothing else the
shell draws depends on the platform theme. Without a portal, Qt falls back to its own Qt Quick dialog. The theme
learns the portal's version a moment after start, so a dialog opened in the first second is Qt's own; a click in
Settings always comes later. The NixOS module must enable xdg-desktop-portal with a FileChooser backend (plan 6.1).

**D52. Other apps can wear the shell's colors; every switch is off by default (plan 2.9; preliminary until the
maintainer has tried it with a separate user).** The maintainer
(October 2026): a main switch (`appColors.enabled`) and one per app (GTK, Qt, kitty, Ghostty, btop, Neovim,
Firefox), all off, because these are the user's own files and another tool (Noctalia, the maintainer's) may
already theme them. The shell (AppTheme.js since D53) runs matugen again from the palette's source color with the
palette's scheme, mode and contrast (palette.py now records them), so an app gets exactly the shell's colors,
rendering only the switched-on apps' templates (`theme/apps/`, matugen's syntax, so community templates fit).
It changes only what it can undo: its own files, a marked block in a config that includes them (GTK's
`@import` goes after the others, so ours wins over an earlier theme's), or one key whose previous value it keeps
and puts back only if the key still holds ours. What it did is in state.json (`appColors.done`), so
turning an app off takes exactly that back out. Terminal ANSI colors are left alone (readability). Firefox goes
through the Pywalfox extension with our own native-messaging host (in Python at first, C since D54; written from
Pywalfox's protocol, as Noctalia does), so no pywalfox program is needed; it pushes new colors when the file
changes. Its manifest replaces another one at the same path (Noctalia's), which is kept aside and put back. The
shell (`AppColorsService`) runs the tool when a switch or the palette changes, and never when nothing is on and
nothing was themed. Tests run in a sandbox HOME only (the maintainer's rule).

**D53. The running shell needs no Python (plan 2.11).** The maintainer (October 2026): what the user runs should be
QML and JS. The palette from the wallpaper (it used `tools/palette.py`) and other apps' colors (a Python `apptheme.py`,
removed) now run in the shell: `Files.js` builds `Process` commands for `sh` that read several files at once,
apply a list of changes (each write to a temporary file renamed over the target, so no reader sees half a file;
moves; removals; signals) and run matugen with a config made on the spot; paths and texts go as arguments, never
into the script. `Palette.js` is `palette.py validate` in JS; `AppTheme.js` is the theming plan as pure functions of
the files' text, so the edge cases test offscreen and the file work is one end-to-end test in a sandbox HOME.
`palette.py` stays as the developer's tool (fixtures, the golden test against matugen). The one exception was the
Pywalfox host: Firefox starts it as its own process and talks over its stdin and stdout, which a Quickshell
shell cannot be; it is C now (D54). Quickshell tests now get a sandbox HOME,
cache and data directory by default.

**D54. The Firefox host is a small C program (plan 2.11).** The maintainer (October 2026): with the host in C, the
user's system needs no Python for Rutile at all. `native/pywalfox-host.c` is one file, no dependencies, built
with strict warnings as errors (`-Wconversion`, `-Wshadow` and more) and hardening (`_FORTIFY_SOURCE`, stack
protector, PIE, full RELRO); `make check` builds it, so a warning fails the gate. It is written to be hard to
break, since C is easy to get wrong: one thread (poll() on stdin, a timeout to look at the colors file); every
read and write loops to completion and retries on EINTR; a frame over 1 MiB ends it (the stream cannot be framed
after one); the JSON reader is strict (RFC 8259, valid UTF-8, surrogates paired), limited to 64 levels, and only
ever reads inside the message; every string sent is escaped and made valid UTF-8; SIGPIPE is ignored so a
vanished Firefox ends it with status 1, not a signal; output never goes through stdio. The colors file is now
plain `key value` lines (`theme/apps/pywalfox.conf`), so the host never parses JSON from disk. The manifest
points at the binary itself (no wrapper); while it is not built, the shell leaves Firefox out and says why.
Tests build it with AddressSanitizer and UBSan (any finding aborts): the protocol, broken JSON and text,
nesting bombs, frame errors, a hostile colors file, the push on change, and seeded fuzzing of both inputs;
mutants of every bounds check are caught. gcc `-fanalyzer` and clang-tidy (bugprone, cert, clang-analyzer)
found nothing beyond Annex K noise. The flake has it as `packages.pywalfox-host`.

**D55. The flake installs the shell as a package and a home-manager module (plan 6.1).** The maintainer (October
2026) wants to test it as a real user. `packages.default` copies `shell/`, `theme/` (templates, roles) and the
compiled host into the package's `share` folder, under `rutile` (the shell finds `../theme` and `../build` beside itself, as in the checkout) and
wraps Quickshell as `rutile-shell` with what the shell runs on PATH and `FONTCONFIG_FILE` pointing at a file that
includes the system's configuration and adds the two fonts, so nothing has to be installed system-wide.
`rutile-shell` with arguments is Quickshell's CLI for the same shell, so `rutile-shell ipc call ...` reaches it.
The home-manager module runs it as a user service bound to `graphical-session.target` (niri-session starts it;
the shell restarts on failure and stops with the session) rather than niri's `spawn-at-startup`, so it can be
restarted and read with systemctl and journalctl. niri's part is one generated KDL file: with home-manager's
niri module it is `include`d at the end of config.kdl (niri merges binds across includes, the later one winning,
and home-manager validates the whole config at switch); without it, it is written to `~/.config/niri/rutile.kdl`
for the user to include, since a module cannot edit a hand-written config. The layer rule is on by default; the
binds are off, because they take keys the user may have bound. Tested without a real login: a headless run of the
built package (`make package-check`), a real home-manager generation with its niri module (so `niri validate`
ran), and the module's options against stand-ins.
