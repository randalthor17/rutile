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

**D56. A popup is done closing when it has faded out (amends D43).** Found in real use (October 2026): the power
menu took too long to go. PopupMotion fired `hidden` only once the scale spring had settled, about 500 ms at speed
1, while the content had faded out after 193 ms (the effects curve); for the full-screen power menu that left the
window, and the blur behind it, on an empty screen for 300 ms. Now `hidden` fires when the fade reaches 0 and the
spring is put at rest (the popup ends at its starting scale, as before). What followed the spring's value for
the closing (the power and polkit veils, a leaving notification's room) follows the fade. In the same change: the
fade had never played on opening (a Behavior does not animate a property's first value), so popups opened at
full opacity; it now starts at 0.

**D57. `rutile-shell` is a script of our own (amends D55).** `rutile-shell --help` printed Quickshell's help and
nothing about the shell. `bin/rutile-shell` (POSIX sh) runs the shell with no arguments (or `run`, or Quickshell's
options), calls the running one with `rutile-shell TARGET FUNCTION [ARGS]`, passes `ipc ...`, `log` and `kill` to
Quickshell for this shell, and has a help that lists every IPC target and function with its arguments. A test
checks that list, and the script's own list of targets, against the IpcHandlers in `shell/shell.qml`, so neither
can drift. The package wraps it with `RUTILE_SHELL_QML` and the runtime PATH (Quickshell included); in a checkout
it finds `../shell/shell.qml` itself. `rutile-shell ipc call ...` works as before.

**D58. Colors in other apps: what real use showed, and niri (amends D52).** On a real user, nothing changed. Two
causes. (1) With no `palette.json` when the shell started (no wallpaper yet, or the first one set later), the
service stopped at "no palette" and its FileView never noticed the file appear. Now it follows the shell's colors
(`Colors.sourceColor`, which PaletteWatcher updates) and, without a palette file, uses that color on the
palette's default scheme, so the apps match the shell either way. (2) Configs home-manager manages are links into
the read-only store; replacing one with an edited file would make the next switch fail. A config that is a
symbolic link is never changed (nor undone): the app's own files are still written, and the error says what to
add in the user's home-manager config. niri is a new switch: the shell writes `~/.config/niri/rutile-colors.kdl`
(focus ring, border, tab indicator, insert hint and shadow colors, the overview's backdrop) and never touches
config.kdl; the home-manager module's KDL has `include optional=true` of it, so with the switch off and the file
gone niri's own colors apply, and niri reloads by itself (it watches included files, missing optional ones too;
colors in an included `border {}` do not turn borders on; both from niri's wiki, Include).

**D59. The flake sets apps up for the shell's look: `programs.rutile.theming` (amends D52, D58).** The maintainer
asked (October 2026) for GTK and Qt theming that works out of the box, kdeglobals, and fonts. Whether the colors
the shell writes are used depends on how each toolkit is set up, which only the user's configuration can do, so
the home-manager module does it, off unless `theming.enable` (each part has its own switch), and turns the
shell's gtk, qt and kde switches on (locked in Settings, as anything set in Nix). Found by screenshotting real apps
(`make theming-check`, a sandbox HOME, a headless sway, home-manager's real modules):
- GTK 4 with libadwaita takes the named colors the shell overrides (its CSS variables are set from them), so
  `gtk.css` importing `rutile.css` is enough. GTK 3's Adwaita compiles its colors in; adw-gtk3 (dark) draws through
  the same names, so GTK 3 apps follow. Plain GTK 4 apps (no libadwaita) use GTK's own theme, also compiled in:
  only adw-gtk3's GTK 4 stylesheet makes them follow. Imported in gtk.css it lay over libadwaita apps, flattened
  their buttons and set their accent back to stock blue (its sheet sets libadwaita's CSS variables to fixed
  colors). Now it comes through `GTK_THEME=adw-gtk3-dark` (theme priority, under libadwaita's own: the buttons stay
  right), and GTK 4's rutile.css (gtk4.css) sets libadwaita's variables from the named colors at user priority, so
  the accent stays ours; on with the GTK part (`theming.gtk.plainGtk4`). Qt's style is Breeze (Fusion looked plain;
  `theming.qt.style`).
- On Wayland, GTK takes theme, font, icons and the dark preference from GSettings (dconf) or the settings portal,
  not settings.ini; home-manager's gtk module writes both.
- Qt: qt5ct/qt6ct (`QT_QPA_PLATFORMTHEME=qt5ct`, which qt6ct answers too) with the Fusion style; their fonts and
  style written with kwriteconfig6 at activation (`qt.kde.settings`), since the shell edits the same files. A font
  there is quoted (QSettings reads an unquoted comma as a list).
- KDE apps (KF6) outside Plasma ignore kdeglobals' `[Colors:*]` unless `[UiSettings] ColorScheme` names a scheme:
  otherwise KColorSchemeManager picks Breeze Light or Dark by itself. The shell's new `appColors.kde` writes the
  scheme (`~/.local/share/color-schemes/Rutile.colors`) and its keys into kdeglobals (each old value kept and put
  back, as with the other keys); the module sets kdeglobals' fonts and icon theme.
- Fonts: Google Sans Flex for GTK, Qt, KDE and fontconfig's default sans-serif. Icons: Adwaita for GTK; Breeze Dark
  for Qt and KDE apps, since Adwaita's icons have fixed dark colors (Kate's sidebar was dark on dark) and lack many
  KDE names (Dolphin's toolbar was empty), while KDE recolors Breeze's to the scheme. Checked in kcalc, Dolphin,
  Kate, a Qt 6 and a Qt 5 app (qt5ct's own windows; qt5ct.conf gets Qt 5's font format). A config that
  home-manager links and that already has our line (gtk.css importing rutile.css) is not reported.

**D60. Qt and KDE apps draw like the GTK apps: Rutile's own Kvantum theme (amends D59).** The maintainer
(November 2026) wanted Qt apps to look like the GTK 3/4 ones, and approved Kvantum but not KvLibadwaita (not
maintained). `tools/gen_kvantum.py` generates our own theme, `theme/apps/kvantum.svg` and `kvantum.kvconfig`,
as matugen templates: libadwaita's look as adw-gtk3 draws it beside them (buttons and entries filled with the text
color at 10/15/30%, 6 px corners, an accent ring on focused entries, accent checks, radios, slider and progress,
pill scrollbars without a groove, menus as rounded popovers with rounded items, gtk.css's color roles). Element
names and keys follow Kvantum's documentation; nothing is copied from its (GPL) themes. The shell's Qt switch
writes it to `~/.config/Kvantum/Rutile/` and selects it in `~/.config/Kvantum/kvantum.kvconfig` (that key kept
and put back like the others); the home-manager module's Qt style is `kvantum` by default (Breeze and Fusion
remain), with Kvantum's Qt 5 and 6 plugins, and KDE apps get it through kdeglobals' `[KDE] widgetStyle`.
Found on the way: the rendered SVG (150 KB) was passed to `sh` as an argument, over Linux's 128 KiB cap per
argument, so the apply step never started and nothing was themed, silently. Rendered files are now copied from
matugen's output folder, and an argument over the cap is an error. Checked by screenshot: a Qt 6 and a Qt 5 app,
kcalc, Dolphin and Kate. Not checked: menus, tooltips, dialogs and other widgets that the check does not open.

**D61. App indicators: our own menu over QsMenuOpener (plan 2.10).** The pill shows SystemTray's items except
Passive ones (the StatusNotifierItem spec's "nothing to show"), in the status window's Row between the bell and
the status pill, so it takes no room when empty. A tray item's own `display()` would show Qt's platform menu,
which is not our style, so the menu is the shared Menu component, extended for what DBusMenu has (separators as
gaps between segmented groups, disabled entries, check and radio marks, the app's icons, a submenu arrow),
filled from QsMenuOpener and shown in a layer-shell window under the item's icon, loaded only while open. A
submenu replaces the list in place with a Back row (as GNOME's), not a cascade of windows. Quickshell already
removes DBusMenu's mnemonic marks (seen with a real app), so the text is shown as given: stripping "_" again
would eat real underscores. Tested offscreen with stand-in items, and end to end with a real tray app (Qt's
SystemTrayIcon under the `qml` runtime, `tests/qs/apps/tray-app.qml`) under headless sway on a private bus.

**D62. Papirus-Dark is the shell's icon theme, and the apps' with theming (the maintainer's choice).** Most tray
apps send an icon name (libappindicator, Electron), which the shell resolves in its own icon theme; the shell had
none set (Qt's default, through the portal platform theme), and neither Adwaita (one app icon) nor Breeze Dark
(684, no Steam or Discord) cover apps. Papirus-Dark has most apps' icons, light symbolic ones made for dark
themes, and KDE's names. `//@ pragma IconTheme Papirus-Dark` sets it for the shell; the package adds it after
the user's data folders (an app's own icon in hicolor is still found); `programs.rutile.theming` uses it for GTK,
Qt and KDE apps (`theming.icons`). `rutile-shell tray iconPath NAME` says where the shell finds an icon. Found on
the way: a Qt tray app resolves its icon name in its own process and sends an empty image when it has no such
icon, so the demo app cannot stand in for apps that send a bare name; its `--icon-name` was removed.

**D63. Colors in other apps: a folder that cannot be written is skipped, and every failure says what failed
(amends D58).** On the maintainer's test user a run ended with "could not change the apps' files" and nothing
recorded: one failed step failed the whole run, and its message was lost. Home-manager can link a whole folder
into the read-only store (`xdg.configFile."nvim".source = ./nvim`), and a file there cannot be written; the read
step now checks each written path's folder (`^PATH`: its nearest existing folder writable?), and the plan skips
such a file with a message, as it does a linked config, so the other apps are themed. The apply script names each
failed step on stderr, and the service handles a step's result only once both of its outputs are read (Quickshell's
collectors have their text at `streamFinished`, which can come after `exited`). Not known: what failed on that
user; the next run's message will say.

**D64. Folder icons follow the wallpaper: a Rutile icon theme over Papirus-Dark (the maintainer's choice).** Papirus
draws each folder in three colors (front `#5294e2`, back `#4877b1`, glyph `#1d344f` in its blue), and its generic
names (`folder`, `user-home`, `folder-documents`, about 85 per size) link to the blue variants. A new switch,
`appColors.folders`, makes `~/.local/share/icons/Rutile`: those generic names at every size, recolored with `sed`
from Papirus's own blue ones (front halfway between `primary` and `inverse_primary`, a mid tone as Papirus's; back
`primary_container`; glyph `on_primary_container`, from `theme/apps/folders.colors`), and an index that inherits
Papirus-Dark. About 1200 small files, so one `sh` function makes them (passed as text they would exceed the
argument cap), built beside the folder and swapped in. Again only when the colors change or the theme is gone;
off removes it. Papirus-Dark is found in XDG_DATA_DIRS (the package and the dev shell put it there). The
home-manager module's `theming.icons.followWallpaper` (on) turns the switch on and gives apps `Rutile` in place of
Papirus-Dark. Apps show new folder colors when they start, as with the colors (D63).

**D65. The palette's style is settings, and light mode reaches every app (plan 5.2).** `style.mode` (dark,
light), `style.scheme` (matugen's scheme types), `style.contrast` (-1 to 1) and `style.seed` (#rrggbb, a new
`pattern` constraint the schema tools, the shell and the Nix module all check). WallpaperService renders from the
wallpaper while colors follow it, else from the seed, and again whenever the source or one of those changes (the
key is remembered in state.json as `wallpaper.paletteKey`; app colors follow that key too, since a mode change
keeps the source color). The templates already took the palette's mode; what had been dark by fixed choice now
follows it: GTK's own dark or light is the shell's to set (libadwaita's `color-scheme`, GTK 3's adw-gtk3 or
adw-gtk3-dark, through dconf), so the home-manager module no longer pins them (its dconf would reset the user's
choice on every switch); the Rutile folder theme inherits Papirus or Papirus-Dark. Quick Settings' Dark theme tile
sets `style.mode` (it had only flipped the shell's own colors, unsaved). Checked by screenshots in light mode
(`make theming-check` takes `--mode light`): GTK 3 and 4, libadwaita, Qt 5 and 6 with Kvantum, KDE apps, and the
shell. Not checked: the real dconf path on a session (the checks use GSettings' keyfile backend).

**D66. Flatpak apps, Java apps, and Pywalfox's light mode.** Flatpak apps cannot see the host's themes or settings,
and installing runtime extensions is a user action, so `rutile-shell flatpak-theming` does it (Settings runs it in a
terminal through a new "action" row kind, a key whose hint has `kind: "action"`): adw-gtk3 and adw-gtk3-dark, and
Kvantum for each installed KDE runtime Flathub has it for, into the user installation; then user overrides giving
read-only access to gtk-3.0, gtk-4.0, Kvantum, kdeglobals and /nix/store (home-manager's links point there),
`QT_QPA_PLATFORMTHEME=kde` (the KDE runtime's platform theme reads kdeglobals) and the Java variable. Home-manager
links the icon themes (Papirus-Dark, and Papirus for light mode) and the font into ~/.local/share
(`theming.icons.flatpak`), the only host places Flatpak apps look. Java apps get `_JAVA_AWT_WM_NONREPARENTING=1`
(niri's advice for xwayland-satellite; `programs.rutile.javaApps`). Pywalfox's light template reads colors 0-15 as
pywal's dark palette (color0 the text, color7 the background's tint); `pywalfox.conf` now puts the dark scheme's
surface in color0 in both modes, and a test ports Pywalfox's palette math to check text contrast in each.
Pywalfox's light background stays its own light grey (it clamps it). Not checked on a real session: the portal's
theme and font names reaching Flatpak apps.

**D67. Settings pages of their own: a view and a backend, each loaded only while the page is open (plan 5.1,
5.2).** Most pages are settings from the schema; Sound, Network, Display and the like show live devices instead.
Such a page names, in `Pages.js`, a `view` (a QML file in `shell/settingsapp/pages/`, which SettingsApp loads
after the page's sections while it is open, giving it `app`, `store` and `backend`) and a `backend` (the
Quickshell services it shows, which SettingsWindow loads only while the page is open, D31). SettingsApp stays
plain QtQuick, so its tests give it a fake backend; the real backend is tested under Quickshell against the
session's own PipeWire, read only, skipping without one. `entries` ({key, title, description, aliases}) are
what search finds on such a page; the view names the matching item `setting_<key>` so it is marked and scrolled
to. About moved onto this. Sound is the first: output and input, each a volume row (slider, mute) and the
devices (`Pipewire.nodes` that have audio and are not streams), choosing one sets Quickshell's
`preferredDefaultAudioSink` (or Source), a hint PipeWire follows when it can; the page shows the default in use.
No per-app volumes (Googlebook's page has none).

**D68. Network and Bluetooth pages (plan 5.2).** Two pages as D67 has them, over Quickshell's Networking
(NetworkManager) and Bluetooth (BlueZ). While a page is open its backend scans (the Wi-Fi device's
`scannerEnabled`, the adapter's `discovering`, through Bindings that restore the old value when it unloads), as
Googlebook's pages do. Wi-Fi networks are one entry per name (the strongest), the connected one first; a secured
network that is not saved asks for its password in a field under it before connecting (`connectWithPsk`), and a
refused password (`connectionFailed` NoSecrets) asks again with "Wrong password". A Bluetooth device that is not
paired is trusted and paired on a click, and connected once paired (only when paired from the page). Pairing uses
BlueZ's default agent: devices that ask to confirm a code need a pairing agent, not built yet. The real backends
are tested read only (`scan: false`); the maintainer's machine has no Wi-Fi card and no Bluetooth adapter, so
there only the wired part and the empty states were seen for real.

**D69. Display: niri's outputs through `niri msg`, changes kept by the user (plan 5.2).** The page reads
`niri msg -j outputs` when it opens and after each change, and changes an output with `niri msg output NAME ...`
(mode, scale, transform, vrr, on, off), one at a time. niri keeps these only until it restarts or its config
changes that output. The shell does not write niri's config (the maintainer's rule), and an included file of
ours would not reliably win: `output` sections are not merged between includes (niri's docs), and which of two
for the same output applies was not established. So each output has "Keep these settings", which copies its
KDL (`output "DP-1" { mode ...; scale ...; }`) to paste into niri's config. The last output on cannot be turned
off from here. Flipped orientations are left to niri's config. Menus on such pages are the app's own one menu
(ChoiceRow, which SettingsApp.choose tells instead of saving a setting). Tested with niri's real JSON and a
stand-in `niri` (tests/qs/bin/niri); the session's niri was not touched.

**D70. Power and Input pages (plan 5.2).** Power is a page of its own (D67) over Quickshell's UPower (the
display device, when it is a laptop battery) and PowerProfiles; Quickshell cannot tell whether
power-profiles-daemon is there, so the backend asks `busctl --system list` once when the page opens, and offers
the modes only then (Performance only where the daemon has it). Input is plain settings (`input.*` in the
schema), because niri has no command to change input at run time: while `input.enabled` is on, NiriInputService
writes them to `$XDG_CONFIG_HOME/niri/rutile-input.kdl`, which the home-manager module includes (optionally)
after niri's own config, so these values win and niri applies them at once; off removes the file. niri 26.04
cannot turn a flag off from an included file (`tap false` does not parse), so tap to click and natural
scrolling are written only when on, and their descriptions say that off leaves niri's config as it is. Not
writing niri's config itself keeps the maintainer's rule. Keyboard layouts are left to niri's config for now (a
text setting needs an editor the app does not have yet).

**D71. Default apps from the desktop files and mimeapps.list, read by the shell (plan 5.2).** Quickshell's
DesktopEntry has no MIME types, and xdg-mime (xdg-utils) would be a new dependency, so the Apps page's backend
reads them itself: one sh/sed script prints the [Desktop Entry] keys that matter of every desktop file in
XDG_DATA_HOME and XDG_DATA_DIRS, and each mimeapps.list in the spec's order (the user's first); `Apps.js` parses
that (the first file with an id wins; Hidden and non-Application entries are dropped; a NoDisplay app is offered
only when it is already the default). A kind (web browser, files, email, pictures, videos, music, text, PDF) has
MIME types; its apps are those that take the first, and its default is the first installed app a list names for
it. Choosing one writes `[Default Applications]` for all its types into the user's mimeapps.list, keeping every
other group and key. When that file is a link (home-manager's xdg.mimeApps), nothing is written and the page
says to set defaults there. No default set shows "Not set": the system then picks one itself (mimeinfo.cache,
which the page does not read).

**D72. Rutile's niri part is a file the user includes; the shelf's right-click menu; a pins page (amends
D55, D70).** The maintainer's rule: Rutile never writes into the user's niri config. With home-manager's niri
module on, the module had appended `include "<store path>"` to config.kdl through `extraConfig`; now it always
writes `~/.config/niri/rutile.kdl` (the layer rule, opt-in binds, and optional includes of the shell's
`rutile-colors.kdl` and `rutile-input.kdl`) and the user adds `include "rutile.kdl"` at the end of their
config.kdl. They are told: install.md, the option's description, a home-manager activation step that prints the
line to add at every switch while config.kdl has no such include, and a toast from the shell (NiriConfigCheck,
which reads config.kdl and watches it, never writes it) when niri's colors or Settings > Input are turned on
without it. The check is a text match on an include line naming rutile.kdl; one included through another file
is not seen (the toast then says it once per run, harmlessly). The shelf had no right-click: a button now asks
for a menu (ShelfApps.menuItems): a pin offers Open, its desktop actions and Unpin; a window offers New window,
the app's actions, Pin or Unpin, and Close window (niri's CloseWindow, or the toplevel's close without niri), in
a layer-shell window above the shelf with the shared menu panel (TrayMenuPanel, now with an `origin`). The
pinned apps setting had no editor: Settings > Shelf is a page of its own listing the pins (move up or down,
unpin, back to the default), apps being pinned from the shelf's or the launcher's right click; pin ids written
as "firefox.desktop" now name the same app as "firefox". `rutile-shell shelf` drives the menu from scripts (the
headless test compositor has no pointer to right click with).

**D73. The include into home-manager's niri config, as an opt-in (amends D72).** D72 stopped the module from
adding Rutile's include to the niri config home-manager's niri module generates; the maintainer's test user,
whose niri config is that module's, had got its colors and binds through it without knowing. Now
`programs.rutile.niri.includeInConfig` (off by default) adds `include optional=true "<XDG_CONFIG_HOME>/niri/rutile.kdl"`
at the end of that module's `extraConfig`: the path in full (the generated config.kdl is a link into the store),
optional so the module's `niri validate` at build time passes while the file is not there yet. With the option on
and no niri module, an assertion stops the switch and gives the line to add by hand. Off, nothing in niri's
config changes (D72).

**D74. Every niri setting from Settings, and Rutile's over the user's (amends D69, D70).** The maintainer asked
that Settings reach niri wherever it can and that Rutile's choices win over config.kdl. The shell writes three
files, each included (optionally) by rutile.kdl, which comes at the end of config.kdl: `rutile-colors.kdl`
(D58), `rutile-settings.kdl` (NiriSettingsService: input while its switch is on, now with an xkb keyboard
layout, and niri's animations at the shell's speed with `motion.niri`; it replaces D70's `rutile-input.kdl`, which
the shell removes), and `rutile-display.kdl` (NiriDisplayService: Display's choices). Merged sections (input,
animations, layout's colors) in a later include replace the user's values, so those win by position. `output`
sections are not merged: tested in a nested niri, the first one for an output applies, so an output section of
the user's beats ours. A `niri msg output` change, though, holds until that output's config changes (also tested:
a reload or another change keeps it, a change to the output's own section drops it). So the shell keeps
Display's choices in state.json (an entry per output, as niri has it after the change) and applies them with
`niri msg output` when it starts and whenever config.kdl changes (NiriConfigCheck now says so); the file covers
the time the shell is not running, for outputs the user's config leaves alone. "Copy for niri's config" (D69) is
gone; an output Rutile keeps has "Back to niri's config" instead (it takes effect at once unless the user's own
config also sets that output, then from niri's next change of it or restart). What an include cannot do: turn off
a flag the user's config sets (`tap`, `natural-scroll`, `animations { off }`: `false` does not parse in niri
26.04). Settings shows a notice on the niri pages while config.kdl does not include rutile.kdl (a notice row
kind, shown while the app's `conditions[when]` holds). Not yet from Settings: niri's keybinds (home-manager only),
the cursor, the layout (gaps, focus ring), workspaces.

**D75. Flags are overridden after all: niri replaces touchpad, mouse and xkb sections whole (corrects D70,
D74).** D70 and D74 said an include cannot turn off a flag the user's config sets, from `tap false` and
`off false` not parsing. niri 26.04's source says otherwise for what matters here: `Input::merge_with` takes an
included `touchpad`, `mouse` (and `trackpoint`, `trackball`, `tablet`, `touch`) section with `merge_clone!`,
which replaces the user's whole; `Keyboard` does the same for `xkb`. So Rutile's touchpad and mouse sections are
the only ones that apply while its input switch is on: a flag left out is off, whatever the user's config says,
and the user's other settings in those sections (dwt, click-method, scroll-method...) do not apply then. The most
used of those, disable-while-typing, is a setting now (`input.touchpadDisableWhileTyping`, on by default); a
keyboard layout set here replaces the user's xkb section (variant and options too). Animations merge `off` with
a logical or, but an `on` flag sets it back (`self.off = false`), so niri's animations following the shell's
speed write `on`. Top-level flags take `false` (`prefer-no-csd false` parses); flags inside sections do not in
26.04, though niri's documentation on main says most do. Checked: the source at v26.04 and `niri validate`; the
effective touchpad settings cannot be read back over niri's IPC, so the replacing itself was not observed.
A KDL parser that copied the user's touchpad, mouse and xkb sections into Rutile's file (so only Rutile's keys
changed) was weighed and dropped by the maintainer: the input switch is off by default, its description says
these sections are Rutile's while it is on, and whoever needs a setting Rutile does not offer keeps it off.


**D76. kitty gets a whole theme, the 16 terminal colors included (amends D52).** D52 left the terminal's ANSI
colors to the user, for readability; the maintainer found that kitty then showed only a new background, as most
text in a terminal is one of those colors, and asked for proper theming through `~/.config/kitty/themes`. The
shell now writes `~/.config/kitty/themes/Rutile.conf`, a kitty theme (its `## name: Rutile` header, so
`kitten themes` lists it), and kitty.conf includes that file itself: choosing it in the kitten would copy it into
current-theme.conf once, and the copy would not follow the next wallpaper. kitty's automatic
`dark-theme.auto.conf` files were weighed too (they need no include at all), and left: they are one slot shared
with the user's own kitten choices, which the shell would overwrite. The six hues come from matugen's custom
colors (Files.js's ANSI table, passed to every app run): harmonized toward the wallpaper's color and given the
palette's tones (80 in dark mode, 40 in light), with the bright ones `lighten: 6`; black and white are the
surface and text roles (color0 surface_container_highest, color8 outline, color7 on_surface_variant, color15
on_surface). A test renders it with the real matugen in both modes and checks the text and hues at 4.5:1 on the
background, the bright ones and color8 at 3:1; across three seeds the lowest seen were 6.1 and 4.1 in light mode.
The old rutile-colors.conf is removed on the next run (an app's `formerly` paths, only when the record says the
shell wrote it); a home-manager config still including it by name logs a missing file until the line is changed.
Ghostty keeps D52's way for now.

**D77. Settings in the launcher, one focused Settings window, a ring for the found setting (plan 5.1).** The
maintainer asked for settings to be searchable from the launcher, a ring that fades on the setting found, a
desktop file, and a reused, focused window. The launcher asks `Model.launcherItems` (the settings app's own
search, its best five) while a query is typed in All; the results are "setting" items (as Quick Settings'
controls) with the page's icon, "Settings · <page>" below, and keywords holding what the search matched besides
the title, so the launcher's ranking (Scorer.js) keeps one found only by its description; a keyword is worth
0.1 of a name match there (apps' are 0.3), so "term" still finds the terminal before a setting whose alias is
"terminal" (the smoke test caught that). Its own search being
the filter keeps the hundred-odd titles from flooding app results through Scorer's typo matching. Choosing one
calls `openSettings(page, key)`, which `ipc call settings openSetting` also reaches. Quickshell cannot raise a
window it already shows, so the shell asks niri: NiriState now keeps each window's pid, and
`NiriService.focusOwnWindow("Settings")` focuses the window of the shell's own process (`Quickshell.processId`)
with that title: GNOME's Settings, also titled "Settings", is not taken for it (tested in a nested niri: the
window's app id is `org.quickshell`, the same for every Quickshell window, so the id alone could not tell).
Without niri nothing is focused, and the window is still reused. The ring is M3's focus indicator over the row
(secondary, 3 thick, the list's corner), drawn by the app over any `setting_<key>` item, so a page view's
groups get it too; it shows at once and fades over long4 with the highlight's end (the row's own selected
tint is gone). The desktop file runs `rutile-shell settings`, which with no function opens the app as it was;
the package writes its full path into Exec.

**D78. The widget renderer: one recursive node, bindings looked up, tones passed down (plan 4.3).** `WidgetHost`
draws a spec (D18) with `WidgetNode`, which picks its node's component by type through a Loader, so only what is
drawn is created (D31); a container's children are `WidgetChild` Loaders of the same file, created with their
node, depth and colors already set (bound afterwards), so nothing fades in from the defaults. Bindings are paths
looked up in `values` ({source: {field: value}}, which the data sources of 4.2 will fill): never evaluated, so a
widget runs no code; a missing value, an object or a function shows a dash, a list is joined. A card (surface
container unless given) or a tile sets the colors its children draw with: a surface tone's On roles, or a tinted
tone's own On role, in which a progress bar also draws (the theme's secondary-container track vanished on a
primary-container card in light mode). A row shares its width equally, except chips, which keep their own width
and pack to the left; a grid has equal columns. A picture is cropped to its aspect with rounded corners (a
MultiEffect mask, created only while a picture shows), a tinted placeholder before. The renderer draws what it
can of a spec that `tools/widget_check.py` would refuse and lists the rest in `problems` (an unknown type, deeper
than 12 levels); a spec of another version draws nothing. Lists repeated over a source's array (the list
example's `{{calendar.events.title}}`) wait for 4.2, which defines what a source's array looks like.

**D79. Widget data sources: a catalog, options in the widget, one object per bound source (plan 4.2).** Nine
sources: clock, battery, system, countdown, media, weather, calendar, http and files. `widgets/sources.json` lists
each one's fields and their types (text, number, fraction, boolean, a list of items, or an open document); it is
the one list: `tools/widget_check.py` refuses a binding to a field it does not name (with the fields it has, for a
model's retry loop), and `tools/gen_sources.py` generates `SourceCatalog.js` for the renderer, whose `problems`
say the same. What a source needs to know goes in the widget's own `sources` object (a countdown's target, a
calendar's path, an http url, another place for the weather or the clock): a template then carries everything
it needs; the schema checks the options, and the checker refuses a binding to a source whose required options
are missing. `WidgetSources` makes one object of `shell/widgethost/sources/` per source the widget binds and
nothing else (D31): a weather widget does not read /proc. Each object only gathers its inputs (a Timer, UPower,
Mpris, a Process reading /proc or an .ics folder, a FileView, an XMLHttpRequest); `Sources.js` works out the
values as plain functions, tested with fixed inputs. Timers follow what is bound: the clock ticks every second only
while `seconds` is, media polls its position only while `progress` is. Weather is Open-Meteo (no key; the place
from the widget or Settings > Widgets, nothing fetched without one) every 30 minutes. The http source fetches only
addresses whose beginning Settings > Widgets lists, each with a host and a slash (so a listed host cannot be
extended into another), at least a minute apart; a widget cannot put data into an address (no bindings there),
so a file it reads never leaves the machine. A calendar reads single events only: repeating ones show at their
first time (RRULE is not expanded), and a TZID time is taken as local. A listRow that binds into a list repeats
per item, at most 8. The settings app gained typed fields for this (numbers, text, lists split at commas and
spaces), as a slider cannot take a latitude.

**D80. A widget preview window before the desktop grid (plan 4.6).** The maintainer asked to try widgets before the
grid (4.4) exists. `rutile-shell widgets preview FILE` (IPC `widgets preview PATH`, `close`, `state`) opens one
FloatingWindow, created only while open (D31), that draws the file with `WidgetSources` and `WidgetHost` and reads
it again whenever it is saved (FileView), with the renderer's problems and the sources' errors listed under it:
the way to write a widget and watch it, and later the Custom widgets app's and the LLM loop's preview. The CLI
makes a relative path absolute, as the shell's working directory is not the caller's; the package ships the
examples. Tried in a nested niri: clock, system, countdown, media (a real player) and weather (the real
Open-Meteo, for Berlin) all filled in.

**D81. The desktop widget grid (plan 4.4).** Each screen has its own widgets, on the shared EditableGrid (1.6,
D17) with gravity off, so a widget stays where it was put and holes are allowed. Cells are square,
`widgets.columns` (default 12) across the screen; a widget is drawn at the top of its cells and scaled down, never
up, when it is taller than them, so all of it shows. Placements are state, not settings: `desktop.widgets` in
state.json, a list of `{id, path, w, h, col, row}` per output name, since the shell writes them as the user drags.
The widget is the file at `path`, read once for every screen and watched (`WidgetLibrary`), so editing a placed
file shows at once. Add offers the user's widgets (`$XDG_CONFIG_HOME/rutile/widgets/*.json`) and the shell's
examples. The layer is `rutile-widgets` on niri's bottom layer, above the wallpaper, in the space bars leave, and
exists only on a screen with widgets or while editing (D31). Outside edit mode its input region is empty, so
clicks reach the wallpaper, whose right-click menu opens edit mode (or `rutile-shell widgets edit`); in edit mode
it takes the pointer and the keyboard, and a bar at the bottom adds, removes and finishes (Escape; Delete
removes), floating over the grid so nothing moves when editing starts. Widgets added over IPC take the focused
output. Not done: keyboard moves, dragging a widget to another screen, a widget's own preferred size.

**D82. Widgets are written by hand; generating them is deferred (plan 4.5).** The maintainer changed the widget
plan: people write widgets as JSON (the spec, D18), and the Ollama bridge, the LLM docs, the eval set and the
local-model trial (4.7 to 4.9, S2, S3) wait. So the Custom widgets app has no prompt box. It is a gallery: the
categories as in Googlebook, each with templates drawn live, and the user's own widgets. Using a template copies it
to `$XDG_CONFIG_HOME/rutile/widgets` (named from its title, -2 when taken), adds the address it reads to
`widgets.httpAllow` (the card says so before), places it on the focused screen, opens the preview and opens the file
in `widgets.editor` (xdg-open when unset). The 30 templates were the local model's task (`widget-templates`); the
maintainer had Claude write them on main, and the brief is retired. Live data is real: Open-Meteo, Frankfurter
(api.frankfurter.dev/v1; .app redirects), CoinGecko and TheSportsDB's public test key 123 (the old key 3 was
switched off). A world clock is one place per widget, at a fixed offset (no daylight saving), because the clock
source takes one `utcOffset`. The http source now drops its fetch when its widget goes, since the gallery's cards
come and go.

**D83. A widget fills the height it is given.** The maintainer found that making a desktop widget taller left it as
it was, with empty cells below. Now the host's height reaches the root node: a card or tile fills it, a column
gives the extra to its last block (card, tile, row, column or grid; with none, the space stays below), and a row
stretches its blocks to one height while chips, stats and text keep theirs. Column and row nodes became
ColumnLayout and RowLayout (Qt Quick Layouts, part of Qt) for this; a widget taller than its cells is still scaled
down. Previews and the Widgets app's cards give no extra height, so they look as before.

**D84. Desktop widgets combine stretching, centering and text scaling.** After D83 the maintainer found bare text
too close to the cell's edge, a widget that cannot stretch stuck at the top, and text the same size in a big
widget. Text scaling did not look right to the maintainer, so it is an option, off by default (`widgets.scaleText`):
then a desktop widget's text and icons scale with its cells against a new widget's 4 x 3 (the smaller of the width
and height ratios, 0.8 to 2 times; paddings stay). By default a widget is stretched or centered, never scaled up. A widget that stretches (WidgetSpec.stretches: a card or
tile, or a column or row holding one) fills its cells. One that cannot is centered in them. One without its own
surface (WidgetSpec.surfaced: a card or tile, alone in a column or row too) keeps a Spacing.lg margin. A widget still
too tall is scaled down to fit, as before. A grid takes no extra height (its cells are fixed rows).

**D85. The widget check runs in the shell.** `rutile-shell widgets check` and `install` (plan 4.6) need the spec's
check where the package runs, and the package has no Python (adding it would be a new dependency). So
`tools/widget_check.py`'s rules for one widget are ported to `shell/widgethost/WidgetCheck.js`, against
`SpecSchema.js` (generated from widgets/spec.schema.json by tools/gen_sources.py) and the source catalog, and the
CLI asks the running shell over IPC (`check`, `checkJson`). The port must find the same problems at the same paths
in the same words: tests/widget_check_cases.py has Python write what it finds in 30 broken widgets and every example
and template, and tst_widget_check.qml compares (it caught Qt counting an emoji as two characters). The Python stays
the repository's gate (it also checks the schema itself and the templates' rules). `install` is the CLI's own copy
into the user's folder under a free name; `--place` asks the shell to put it on the desktop. The preview window
lists the check's problems too. `docs/widgets.md` is the guide for people writing widgets.

**D86. Editing widgets clears the screen; right-click edits; Use only adds.** From the maintainer's first try:
(1) edit mode should get the apps out of the way. niri has no minimize, so every output switches to its last empty
workspace (the focused output last, so the keyboard stays), and Done switches each back unless the user moved on
(NiriState.showDesktop and hideDesktop). (2) A right-click on a widget went through to the wallpaper's menu; now the
widgets' layer takes the pointer on the widgets' cells (an input region from the grid's slots), and a right-click
there starts editing with that widget selected. (3) Use opened a preview window, the editor and the desktop at once.
Now Use copies and places it and says so in a toast; editing is "Edit" under Your widgets (editor and preview).
(4) xdg-open may open JSON in a browser: the user sets `widgets.editor`.

**D87. System monitor widgets and charts.** The maintainer asked for CPU, GPU, RAM, VRAM, power and temperature
widgets, and the charts they need. Data: `system` gains per-core use, frequency, swap, the root disk (df), network
rates (every interface but loopback) and histories; a new `gpu` source reads amdgpu's sysfs (use, VRAM, the starred
clock, its hwmon's temperatures, power and fan) and nvidia-smi's line when installed, showing the card with the most
VRAM unless `card` names one (this machine has an iGPU and an RX 9060 XT); a new `sensors` source reads every hwmon
temperature (readings at or below 0 or above 150 dropped: boards report -55 for missing sensors) and RAPL's energy
counter for the processor's power, which is root-only on most systems, so that field is usually missing. They read
every second (`every`, 0.5 to 10) and keep 60 samples (`history`); a field the hardware lacks is missing, and shows a
dash. A new catalog field type, `numbers`, is a list of numbers. Charts: one node, `chart`, with `kind` line, area,
bar, pie, donut or gauge, drawn with Rectangles and QtQuick.Shapes' curve renderer (no Canvas). The maintainer saw
a few samples stretched across the width hide the trend, so a line or area chart spans a fixed window (`points`, 60),
filling in from the right and then scrolling. The checker (Python and its JavaScript port) knows the node and the new
options; a "System" category of five templates joins the Widgets app.
After a first look the maintainer asked for download and upload in one graph, real names, and hardware other than
amdgpu. A line or area chart takes `series` of histories, one line each on one scale, with a legend of each newest
value. `system.cpuName` comes from /proc/cpuinfo (read once, trademarks and core count dropped). Card names come
from libdrm's amdgpu.ids (the exact marketing name by device and revision; libdrm is in Qt's closure already), then
hwdata's pci.ids (its bracketed name after the vendor; hwdata added to the package with the maintainer's approval),
then nvidia-smi's own; the package points RUTILE_AMDGPU_IDS and RUTILE_PCI_IDS at them. The gpu source reads i915's
and xe's clock and a discrete Intel card's energy counter (power from two readings), nouveau's hwmon, and leaves out
what a driver does not report (Intel has no use percentage), rather than showing 0. The scripts use sed, not grep,
which the package does not put on PATH.

**D88. Googlebook's windows: a window rule from Settings, and our own title bars (plan 3.1).** niri draws no title
bars and decides how windows look through window rules. Settings > Windows (`windows.*`) adds one rule for every
window to rutile-settings.kdl, the file the shell already writes for input and animations (D74): floating when
opened (`open-floating`), a corner radius with clipping, niri's shadow, and no focus ring or border, each its own
switch. The rule comes after the user's (rutile.kdl is included last), so its values win, as D74 has it; the main
switch is off by default, like input, since floating every window changes how niri is used. Only the focus ring's
"on" writes nothing, leaving ring and border to niri's config. The shadow takes niri's own softness, offset and
color. Our own app windows (Settings, Widgets, the widget preview) had Qt's plain Wayland title bar; now Qt's
decorations are off (`QT_WAYLAND_DISABLE_WINDOWDECORATION`, a pragma in shell.qml) and they draw an M3E one
(AppFrame, TitleBar): the app's icon and name on the window's color, maximize or restore and close as icon buttons,
the compositor's move on a press of the bar (Quickshell's startSystemMove), maximize on a double click or the middle
button, and edges to resize by (startSystemResize). No minimize button: niri has no minimized state (D86 uses an
empty workspace for the desktop instead). Tested in a nested niri: a maximized floating window goes to niri's columns
maximized, and restoring brings it back floating at its size. Third-party apps keep their own decorations: GTK's
header bars, and Qt's (the theming of D59 covers their colors).

**D89. Quick Settings keeps its tiles, offers the rest, and opens detail pages (plan 2.6).** The tile layout was
kept in memory only. It now goes to state.json (`quicksettings.tiles`, like the desktop's widgets: it is the shell's
state, not a setting with a schema); a saved layout is made safe before it is shown (known tiles once each, widths 1
or 2), and nothing saved means the defaults. Edit mode lists the tiles not shown as chips under the grid; a click adds
one at the end, wide when it has a detail side. Two tiles join: Do not disturb (the notifications' switch) and Power
saver (PowerProfiles' power-saver mode, off meaning balanced). Quickshell cannot tell whether power-profiles-daemon is
there and PowerProfiles is not touched until it is known, so `busctl` looks for it the first time Quick Settings
opens, as the Power page does. Night light is left out: it needs a gamma program, a new dependency. The Wi-Fi and
Bluetooth tiles' bodies open detail pages in place of the panel's contents, as Googlebook does, instead of opening
Settings, so the lists sit next to the switch. (Written first as "Network and Bluetooth have no Settings pages yet":
wrong, they have since D68; the Quick Settings pages repeat their lists through Details.js.) What the pages
list and what a click does are plain functions (Details.js) over plain lists the services build, so they test without
NetworkManager or BlueZ. A password is typed in a field under its network and goes to NetworkManager with
`connectWithPsk`; networks needing more (802.1X) are listed but do nothing. A Bluetooth device not paired is trusted
and paired, and the service connects it when BlueZ reports it paired. The sound button opens Settings > Sound.

**D90. A press on the shell's own desktop closes its popups (amends D41).** D41 closed Quick Settings when its
window lost keyboard focus, and left a gap: on niri a click on the wallpaper or on a bar moves no focus, so the
panel stayed open. Those surfaces are the shell's own, so they say so: a press on the wallpaper, on a desktop
widget, on the shelf between its buttons, or on the clock closes Quick Settings, the launcher and the notification
list (`closePopups` in shell.qml). Still rejected: D41's full-screen catcher window (a screen-sized buffer while
open). A press on a shelf button does what the button does (the launcher button still toggles the launcher). Not
covered: a press on another program's layer surface (another bar), which tells the shell nothing. Tested offscreen
for the shelf and the widgets; the wallpaper's and the clock's wiring was not clicked with a real pointer (neither
the headless sway nor the nested niri has one the tests can drive).

**D91. Night light through wlsunset.** The maintainer approved wlsunset as a dependency for Quick Settings' Night
light (2026-11-04). It is in the package's PATH and the dev shell. wlsunset follows the sun between a day and a
night temperature and has no "always on"; the shell runs it with the night temperature and one kelvin more for the
day (`-t T -T T+1`), so the screen is warm at any hour while the tile is on, and stopping it hands the gamma back
(the compositor restores it when wlr-gamma-control's client goes). On or off is shell state (state.json, back on
with the shell); the warmth is a setting (`nightLight.temperature`, 2500 to 6000 K, Settings > Display); a new
warmth restarts it. A wlsunset that stops by itself turns the switch off and shows its last line in a toast: another
gamma program (gammastep) holds the outputs, or the compositor has none (niri nested in a window, where it could
not be tried: niri's winit backend has no gamma control). niri supports wlr-gamma-control on a real
screen; only its nested (winit) backend lacks it. Sunset to sunrise (the maintainer's request, the same day):
`nightLight.schedule` runs wlsunset with the daylight temperature for the day, at the weather place's latitude and
longitude (`-l -L`), or, with no place set, at `nightLight.sunset` and `nightLight.sunrise` (`-S -s`); the tile says
"Sunset to sunrise" while on. NightLight.js builds the command. gammastep was the alternative, larger (GTK tray, geoclue) for the same job.

**D92. Settings' choices in a dialog (plan 5.1).** A setting with choices opened a menu under its row; Googlebook
asks in a dialog ("Choose modifier key" in the reference): headline, a line on what it does, the choices with the
current one checked, Cancel and Done. Now that the kit has a Dialog (1.5g) the settings app does the same, centered
over a scrim: a click picks (nothing is applied yet), Done applies the pick (the current one picked applies nothing),
and Cancel, Escape or a press on the scrim leave the setting as it was; the arrows move the pick and Enter is Done.
The headline is the setting's title and the line its description (a page's own ChoiceRow gives its text and
supporting text). More than six choices scroll. The app's interface did not change (`toggleMenu`, `menuKey`,
`settingChoice_N`), so pages kept working; their tests now press Done.

**D93. The calendar under the clock (plan 2.12).** Googlebook's clock opens a calendar; Rutile's clock only closed
the popups (D90). A press now closes the others and toggles a calendar popup under it, built as the notification list
(D41): a LazyLoader'd layer-shell window that takes the keyboard, closes on focus loss or Escape, keeps its tallest
size with a mask, and grows from the top left with PopupMotion. It reads the folder each time it opens and runs
nothing while closed (D31). Events come from .ics files only: `calendar.folder` (default `~/.calendars`), searched
with the folders right in it (sh globs: the package's PATH has no find), which is the layout vdirsyncer writes, so Google or CalDAV calendars arrive by running
vdirsyncer; bundling vdirsyncer (and its account setup) would be a new dependency and was not done. Repeats are
expanded in `shell/calendar/Calendar.js`, shared with the widgets' calendar source (which before showed a repeating
event's first time only): the common RRULE parts (FREQ daily to yearly, INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY),
EXDATE and RECURRENCE-ID; a rule with anything else shows its first time, as before. Times repeat in local time and
a TZID time is taken as local: right for events made where the user is, an hour off for one made in another zone
around a DST change. Six weeks are always shown, so the popup keeps its size from month to month. The widget source
keeps its required `path` (no change to the widget spec).

**D94. Google Calendar through its secret iCal address.** The maintainer asked for Google Calendar support
(2026-11-04) and left the choice to Claude. Considered:
1. Sign in with Google in the shell. It needs an OAuth client. Google's device flow (a code typed on another
   device) does not allow calendar scopes; it allows only sign-in, two Drive scopes and YouTube. The loopback flow
   needs a listener that Quickshell lacks. A client shipped with Rutile would need Google's verification for a
   sensitive scope, and Google's terms forbid publishing its secret in open source (vdirsyncer's reason for having
   none).
2. vdirsyncer's google storage. Every user must create a Google Cloud project, enable CalDAV and make a desktop
   OAuth client first. It also adds Python and vdirsyncer[google] to the package.
3. GNOME Online Accounts with evolution-data-server. GNOME's verified client gives a real sign-in, but it brings the
   GNOME data stack, needs gnome-control-center to add the account, and reading events would go through D-Bus calls
   the shell does not have.
4. The calendar's secret address in iCal format, which Google gives for every calendar (Settings, Integrate
   calendar). Chosen: no dependency, no Google project, nothing to sign in to, and the same setting serves Outlook,
   iCloud, Proton and Nextcloud.
`calendar.feeds` lists the addresses (webcal:// read as https://). `CalendarFeeds.qml` fetches each with
XMLHttpRequest when the calendar opens. It keeps an answer only if it is a calendar: a sign-in page or an error
leaves the last copy, and the popup notes the failure. That copy is kept in `$XDG_CACHE_HOME/rutile/calendars`,
one file per address named by a hash, so the secret is in no file name, and it shows at once and offline.
Costs:
- Read only.
- Each calendar has its own address.
- Anyone with the address can read the calendar. The setting says so, and that Nix settings put it in the
  world-readable store.
- How soon Google's address reflects a change was not measured: no Google account was used. Third-party reports
  about Google's polling of *other* feeds (hours) do not apply to its own export, but this is unverified.
A real sign-in can come later through option 3, if the maintainer approves that dependency.

**D95. Google Calendar through GNOME Online Accounts and evolution-data-server.** The maintainer wanted a real
sign-in and editing, and chose GNOME Online Accounts (2026-11-04). That approves these dependencies:
gnome-online-accounts, evolution-data-server, gnome-calendar and gnome-online-accounts-gtk. The parts:
- **Sign-in.** GNOME Online Accounts signs in through GNOME's verified Google client, in the browser
  (goa-oauth2-handler). Its window outside GNOME's Settings is XApp's gnome-online-accounts-gtk, opened from
  Settings > Calendar > Online accounts. The tokens go to the Secret Service (gnome-keyring).
- **Sync.** evolution-data-server syncs the calendars.
- **Editing.** GNOME Calendar edits events and chooses which calendars show. A click on a synced event opens it
  there (`--uuid <calendar uid>:<event uid>`, unverified against GNOME Calendar's own format). "Open Calendar" opens
  the app.
- **Reading.** The shell reads through `rutile-calendar` (native/calendar.c on libecal; the second compiled
  program after D54). Quickshell has no D-Bus client of its own, and one-shot `busctl` calls cannot work: the data
  server closes a calendar the moment the connection that opened it goes. The helper has three commands:
  - `events FROM TO` prints every shown calendar's events in the range, one JSON object per line. The data server
    works out the repeats, exceptions and time zones itself, which the .ics reader (D93) only approximates.
  - `refresh` asks each calendar to sync now.
  - `sources` lists the calendars.
  It opens the calendars side by side and waits 1 s for each to be online. Local calendars never report online
  and took the whole 10 s wait first tried; a calendar that is not online still answers from its copy. Since
  2026-11-05 only a refresh or an add on a server's calendar waits; a read and a local calendar never do, which took a
  read from about 1 s to 0.01 s. evolution-data-server itself starts on first use (D-Bus activation), about 1.5 s on
  the maintainer's machine with an online account, and the popup said "No calendars yet" meanwhile. So the shell
  reads no time at all 3 s after it starts, which starts it (it then stays running, as in GNOME; that memory is the
  data server's, not the shell's), and the popup shows neither "No events" nor "No calendars yet" until the data
  server has answered (`loading`). On a test account with three Google calendars, a read still took 1.6 s on every
  open (0.39 s right after another): the data server unloads an account's calendars soon after the last client
  leaves. Keeping a reader connected would hold them, and a process, all the time; instead `EdsCalendar` keeps what
  the last read printed in `~/.cache/rutile/calendars/` (one file for the popup, one for the widgets) and shows it
  until its own read comes back, as the calendar addresses do (D94).
- **The popup.** `EdsCalendar.qml` runs the helper when the popup opens: it reads, asks for a sync, then reads
  again. It reads a new month's six weeks once both ends have changed (`Qt.callLater`: the command's binding lags
  the range).
- **The system.** It must run evolution-data-server, gnome-online-accounts, gnome-keyring and dconf (NixOS
  `services.gnome.*`; docs/install.md). A home-manager module cannot add D-Bus services to the session bus. Without
  them the helper exits 2 and the popup shows the other sources.
- **Tests.** tests/test_calendar_helper.py runs a real data server on a private bus with calendars in a temporary
  home. tests/qs/tst_eds_calendar.qml and the wayland smoke use a fake helper. Signing in to Google itself was not
  tried.

**D96. Releases tagged afterwards.** 132 commits had gone untagged since v0.5.1 (2026-10-11). The maintainer chose
(2026-11-04) to tag the milestones they passed rather than one release for everything:
- v0.6.0 at 367085a: the component kit;
- v0.7.0 at c0f8cc0: the shell core;
- v0.8.0 at 813615e: the Settings app and the Nix package, the first real install;
- v0.9.0 at 776217b: theming, app indicators, Settings pages, widgets;
- v0.10.0 at the commit that split the changelog.
Each older commit passed `make check` in a worktree of its own before it was tagged. The cut first proposed for
v0.7.0, 9287215, failed there: a plan-only commit naming D50 and `shell/settingsapp/` before they existed. The
commit before it was tagged instead. CHANGELOG's Unreleased entries went to the version whose range holds the
commit that added them (`git blame`). Each section says it was tagged afterwards and at which commit. From here on,
tag at each milestone when it lands.

**D97. The greeter (plan 6.2).** A sign-in screen in the shell's look on greetd, with Quickshell's `Greetd`.
- **Where it runs.** greetd's default session is a niri of its own that starts `rutile-shell greeter` and quits after
  it (`nixosModules.greeter`). niri is the compositor the user already has, so outputs, input and scaling behave as in
  the session; cage or sway would be a second compositor to configure. niri's log goes to the journal
  (`systemd-cat -t rutile-greeter`), not over the console it starts on.
  The option is `services.displayManager.rutile-greeter` (the maintainer's choice, before the first release with
  it): where NixOS keeps sign-in screens (GDM, SDDM, Noctalia's greeter), not `programs.rutile` as first named.
- **What it shows.** The lock screen's face (LockPanel gained `secret` and `placeholder` for greetd's other questions)
  and a bottom row as ChromeOS's sign-in screen: Shut down, Restart, then the person and the session as menus when
  there is a choice. People: /etc/passwd, uid 1000 to 59999 with a login shell. Sessions: the system's
  wayland-sessions (`services.displayManager.sessionData.desktops`). The last person and each person's last session
  are kept in /var/lib/rutile-greeter/state.json. The greeter runs as `greeter` and cannot read anyone's home, so its
  wallpaper and palette are module options (a store path), the palette defaulting to the golden one.
- **Talking to greetd.** `GreeterSession` asks greetd for a session and answers its questions. A failed sign-in, or
  another person chosen mid-way, cancels and begins again only after a pause (300 ms): Quickshell is Inactive at once
  after a cancel, and a session created before greetd's reply to the cancel takes that reply for its own, after which
  its answers are out of step with greetd's questions (seen against fakegreet, and as a stuck second sign-in). A
  failure shows "Wrong password. Try again." (PAM's "AUTH_ERR" goes to the log), and greetd's connection error just
  after a failure is not shown.
- **Starting the session.** greetd joins the command's words with spaces and runs them with /bin/sh after reading
  /etc/profile, so the session's own Exec words are sent, each shell-quoted when needed. A first version wrapped them
  in `sh -l -c 'exec "$@"'`; greetd's joining lost the quotes and every session ended at once. Only the VM test,
  which really starts a session, could show it: fakegreet never runs the command.
- **Tests.**
  - Offscreen: the parsing, choices, prompts and the panel.
  - Quickshell against greetd's fakegreet (`// under fakegreet`): the questions, a failure and the launch.
  - The real greeter under headless sway with fakegreet (`qtws.py test-greeter`, in `make check`): choosing, a wrong
    answer, signing in, what is saved.
  - A NixOS VM with real greetd and PAM (`nix build .#checks.x86_64-linux.greeter`, not in `make check`): a wrong
    password, then the right one starts alice's remembered session as alice. niri cannot draw without a GPU, so the VM
    runs the greeter under sway with pixman instead of niri.
- **Not done.** Avatars, the user's own wallpaper and colors without copying them into the configuration, keyboard
  layout choice, and a run on a real machine.

**D98. A built-in wallpaper, shared with the sign-in screen** (the maintainer's request, 2026-11-04, after trying the
greeter):
- **The session button always shows**, even with one session, so the session is visible before signing in.
- **Rutile's own wallpaper.** `theme/wallpapers/rutile-default.jpg` is rendered from `rutile-default.svg`: soft shapes
  in the default seed's blue, drawn for the project, MIT. The desktop, lock screen and greeter use it while nothing
  else is set. Settings > Wallpaper says "Rutile's own". The palette keeps coming from the seed color while it shows:
  the image is drawn in the seed's colors, and every app's colors stay what they were without a wallpaper.
- **Sharing with the greeter.** The greeter runs as `greeter` and cannot read anyone's home. The module makes
  `/var/lib/rutile-greeter/users/<name>` for each normal user, owned by them, 0755. That person's shell copies its
  wallpaper and `palette.json` there whenever either changes (WallpaperService, `Files.greeterShareCommand`): only
  what changed, each written beside and renamed over, nothing when the folder is missing or not writable. The greeter
  shows the chosen person's wallpaper and colors, falling back to the module's `wallpaper` and `palette`, then to
  Rutile's own.
- **Costs.**
  - Anyone on the machine can read a person's wallpaper and colors, as anyone can see them on the sign-in screen.
  - Nothing is shared until that person's shell has run once.
  - A person added later gets a folder at the next rebuild.
- **Alternatives.**
  - A system service copying from homes: it reads every home as root.
  - AccountsService, which keeps a background per user only for GNOME's greeter: another daemon and no colors.

**D99. The person's picture on the lock and sign-in screens** (plan 6.2, 2026-11-04):
- **Where it comes from.** `~/.face`, the file GDM, SDDM and LightDM read, else the picture GNOME Settings keeps for the
  person (`/var/lib/AccountsService/icons/<name>`), else their initial on a circle in the primary container color.
- **Shown** above the name in a circle (LockPanel's `avatar`), on the lock screen and the greeter alike.
- **Shared** as the wallpaper is (D98): the shell copies `~/.face` to the greeter's folder as `avatar` when it starts,
  and removes it there when `~/.face` is gone. The greeter tries that copy, then AccountsService's. The shell and
  the greeter look the file up once with `Files.firstReadableCommand`, so a missing file never reaches an Image
  (Qt warns on each one).
- **Costs.** A new `~/.face` shows at the next start of the shell, not at once. Anyone on the machine can read the copy.
- **Alternatives.** AccountsService's D-Bus API: another daemon for one picture, and GNOME Settings' files are read
  anyway when they are there. A picture setting in Settings: later, if `~/.face` proves awkward.

**D100. Hidden Wi-Fi networks through nmcli** (plan 2.6, 2026-11-04):
- **What.** Under the Wi-Fi page's list, "Hidden network" asks for a network's name and its password (left empty for
  an open one) and joins it. While it does, the row says "Joining <name>…"; a failure shows a toast ("Couldn't join
  <name>"); a success shows as the network connected in the list.
- **How.** Quickshell's Networking only joins networks a scan has found, and a hidden one is never in a scan.
  `shell/services/hidden-wifi.sh NAME open|psk` asks NetworkManager through `nmcli` (part of NetworkManager, which
  Wi-Fi needs anyway; nothing new to install): it reuses a saved connection of that name (marking it hidden) or adds
  one as hidden, then brings it up, and removes a connection it added when joining fails, so a mistyped name or
  password leaves nothing behind. The password goes to the script on stdin and on to nmcli as its `passwd-file`
  through a pipe (`printf` is the shell's own), so it never appears in any process's arguments, which every user
  can read, nor on the disk. NetworkManager keeps it with the connection, as for a visible network.
- **Checked** in a NixOS VM with a simulated radio (`nix build .#checks.x86_64-linux.hidden-wifi`, not in
  `make check`): hostapd offers a hidden WPA2 network and a hidden open one, NetworkManager is the client, and the
  script joins both; a wrong password and an unknown name leave no connection; the saved password (with quotes,
  `$`, `;` and spaces) joins again without asking; joining again reuses the connection. The QML side runs the real
  script against a stand-in nmcli (`tests/qs/tst_hidden_wifi.qml`).
- **Costs.** A wrong password fails only after nmcli's 90 seconds (NetworkManager keeps retrying with the same
  password), so the row says "Joining…" that long. Finding a hidden network takes an active scan of every channel
  (about 15 seconds in the VM). Not tried with real hardware. Enterprise (802.1X) hidden networks are not offered.
- **Alternatives.** NetworkManager's D-Bus API directly (AddAndActivateConnection with the secrets): no stand-in
  as simple as a fake nmcli for the tests, and more code for the same result. `nmcli device wifi connect ... hidden
  yes password ...`: puts the password in the arguments.

**D101. Adding an event from the calendar popup** (plan 2.12, the maintainer's list, 2026-11-05):
- **What.** A + beside the chosen day's title opens a form in place of its events: the title, All day or a start and
  an end time (typed as 9:30, 21:30, 9pm...; the next full hour today, else 9:00, an hour long), and which calendar
  when there is more than one. Save adds it; the form stays with the reason when that fails (a read-only calendar,
  the server). Enter in a field saves, Escape closes the form (not the calendar), and the arrows move the day only
  while the form is closed.
- **Where it goes.** Only to evolution-data-server's calendars (Google and the other GNOME Online Accounts ones, and
  local ones): `rutile-calendar add SOURCE timed|allday START END TITLE` creates the event with libecal, in the
  local time zone (its VTIMEZONE added to the calendar), or as dates for an all-day one; EDS sends it to Google with
  its next sync. `sources` now marks the data server's default calendar, which the form chooses first; calendars
  made from contacts (Birthdays) and weather are not offered. The calendar folder and the iCal addresses are
  read-only copies and take no events; without EDS calendars the + is not shown.
- **Checked** with a real evolution-data-server on a private bus (an event and an all-day one added and read back,
  the time zone kept, refusals' exit codes), the QML side with a fake helper, the form offscreen. Not tried with a
  real Google account.
- **Not done.** Editing and deleting (GNOME Calendar does them; a click on an event opens it there), repeats,
  reminders, a location, guests.
- **Alternatives.** Opening GNOME Calendar to add it: a whole app for a title and a time. Writing an .ics into the
  calendar folder: vdirsyncer users only, and nothing reaches Google until their next sync.

**D102. The widgets' calendar source shows the user's own calendars** (plan 4.2 and 2.12, 2026-11-05):
- **What.** The calendar source's `path` is optional now. Without it a widget shows what the calendar under the
  clock shows: Settings > Calendar's folder, its addresses (fetched every 30 minutes, their saved copies at once)
  and the accounts' calendars in evolution-data-server (Google through GNOME Online Accounts), read every 5
  minutes for today and the `days` ahead. With a path it reads only that, as before, and starts nothing else. The
  Daily update templates dropped their `~/.calendars` path, so they show Google without the user typing anything.
- **How.** CalendarSource loads CalendarFeeds (only when there are addresses) and EdsCalendar (without listing
  calendars to add to) in Loaders that are active only without a path (D31). The source is only made for a widget
  that binds `calendar` (D79).
- **Checked** in Quickshell with a fake rutile-calendar and a folder from Settings: both calendars' events
  together, soonest first; the data server asked for the widget's days; a widget with a path never asks it. The
  addresses part is the popup's CalendarFeeds, tested there, not again here.
- **Costs.** Each such widget runs the helper every 5 minutes (about a second; no process stays). Two widgets
  read twice: no sharing between widgets yet.

**D103. NavRail: the collapsed M3 Expressive rail** (plan 1.5, 2026-11-05):
- **What.** A column of destinations (icon in a 56 x 32 pill indicator over a labelMedium label), 96 px or 80 px
  (`narrow`), a header slot at the top for a menu button or FAB, the first destination the rail's top space (44)
  down. The active one has the secondary container indicator, grown from its middle on the fast spatial spring (as
  Compose animates the indicator's width), a filled icon and a secondary label. It reports `chosen(id)` and never
  changes `currentId` itself, like Switch's controlled mode (D33).
- **Tokens.** Compose's expressive rail files (the "WideNavigationRail" ones, vendored today): collapsed, expanded,
  colors, vertical item. The old M3 `NavigationRailTokens.kt` is gone upstream.
- **Not done.** The expanded rail and the collapsed-to-expanded morph; badges; arrow keys. Nothing in the shell uses
  the rail yet; Settings keeps its list of pages (5.1, D50), which is what ChromeOS's Settings shows.
- **Cost.** About 80 KiB per destination (docs/memory.md).

**D104. The package's version is the release's; history rewritten once to make it so** (the maintainer's request,
2026-11-05):
- `nix/package.nix` and the Firefox host in `flake.nix` said `0.1.0` at every release. They now carry the latest
  release in CHANGELOG.md, and `tests/test_handoff.py` fails when they do not; the release protocol in the handoff
  sets it.
- The maintainer asked for the tagged commits to carry their own versions, so the history from the package's first
  commit (94e3673, 2026-10-27) on was rewritten (`git filter-branch`): each commit's version is the release at or
  before it (0.7.0 until 0.8.0, and so on), and v0.8.0 to v0.11.0 were moved to the rewritten commits and
  force-pushed. Nothing else in any tree changed. This breaks the rule of never moving a pushed tag, once, by the
  maintainer's decision: the project has no other users, and their own NixOS config is updated with
  `nix flake update rutile`. Commit IDs in older commit messages after that point no longer resolve; the ones in the
  docs were updated.

**D105. Time zones in .ics files from their own VTIMEZONE** (plan 2.12, 2026-11-05):
- **What.** A time with a TZID (`DTSTART;TZID=America/New_York:20261210T090000`) is now that zone's time, not local
  (D93 took it as local). `Calendar.js` reads the file's VTIMEZONE: each STANDARD and DAYLIGHT part's offsets,
  DTSTART, RDATEs and yearly RRULE (BYMONTH with one BYDAY like `2SU` or `-1SU`, the old `BYMONTHDAY=8..14;BYDAY=SU`
  form, or a fixed date; UNTIL ends a rule, so the pre-2007 US rules stop). The offset at a time is the one of the
  part that began last before it. DTEND, EXDATE and RECURRENCE-ID use the zone too, and a repeating event repeats on
  its zone's clock (9:00 in New York stays 9:00 there across its DST change, so it moves an hour for the user).
- **Why the file's own zones.** RFC 5545 requires a VTIMEZONE for every TZID used, and Google, Outlook and tzurl
  write them. Qt's JavaScript has no Intl time zones, and asking the native helper (libical's zone database) would
  mean a process per read for the folder and the addresses. A TZID the file does not describe is still taken as
  local.
- **Not done.** A wall time in a DST gap takes the offset after the change, and one in an overlap the offset
  before it; a zone rule with several weekdays uses the first. Events from accounts (D95) were already right: EDS works their zones out.

**D106. Plain tooltips, first on the shelf** (plan 1.5 and 2.4, 2026-11-05):
- **What.** `Tooltip` (shell/components) is M3's plain tooltip: Compose's `PlainTooltipTokens.kt` (inverse surface
  and its text, the extra-small corner, bodySmall) and the sizes `Tooltip.kt` keeps in code (8 x 4 padding, at least
  40 x 24, at most 200 wide, 4 from what it explains), both vendored and checked by `gen_components.py`. It grows in
  with PopupMotion and says `hidden` when gone. The rich tooltip (title, actions) is not done.
- **The shelf.** Hovering a button for 500 ms shows its tooltip: a pin's app name, a window's title (its app's name
  without one). From one button to the next it changes at once, as desktop tooltips do; it goes when the pointer
  leaves the buttons, presses one, or opens its menu. The delay is Rutile's choice; Compose shows a tooltip on hover
  without naming a delay in its tokens. The tooltip is a layer-shell surface of its own above the shelf (it could not
  draw outside the shelf's), taking no input, loaded only while it shows (D31). `ipc call shelf tooltip TEXT` shows
  one for scripts and the smoke test.
- **Cost.** 58.7 KiB per tooltip, and only while one shows (docs/memory.md).

**D107. Keyboard editing in the EditableGrid** (plan 1.6 and 4.4, 2026-11-05):
- **Keys.** In edit mode, with the grid focused (a click on an item focuses it): Tab and Shift+Tab select, going
  round; the arrows move the selected item a step on screen; Shift with the arrows resizes it as a handle would,
  Shift+Right and Shift+Down growing it whichever way the grid runs. Every step commits through the owner, as a drop
  or a released handle does.
- **Moves.** A one-cell drag, through the same code as the pointer, except sideways with gravity: there a drag one
  cell over mostly lands back where it was or sends a neighbor a row down, because gravity reflows in reading order.
  So Left and Right swap the item with the one before or after it in reading order and let the rest flow, refusing
  a swap that would outgrow `maxRows`. That is how Quick Settings tiles read: in order.
- **Not done.** Moving between screens, or into the grid from outside. Screen reader support is out of scope: the
  shell has one user, who does not use one (the maintainer, 2026-11-05).

**D108. Night light and Power saver detail pages in Quick Settings** (plan 2.6, 2026-11-05):
- **What.** Both tiles are dual-target now, like Wi-Fi: the icon toggles, the body opens a page. Night light's has
  the warmth (2500 to 6000 K in 100 K steps, the setting's range), Sunset to sunrise, and "Display settings" for the
  sunset and sunrise times (`settingsPageRequested("display")`). Power saver's lists power-profiles-daemon's modes,
  Performance only where the machine has it, the current one marked. Added tiles of either kind come wide.
- **Saving the warmth.** Every change to `nightLight.temperature` restarts wlsunset, so the slider saves 300 ms after
  it rests and never while held: one save per drag or run of key steps.
- **The slider's ticks.** A stepped slider drew a dot at every stop: 35 here, and about 1 MiB for 100 steps.
  `Slider.ticks: false` leaves them out (80 KiB), still snapping to the steps.
- **Not done.** Pages for Microphone (input devices), Dark theme, Airplane mode and Do not disturb.

**D109. The Microphone page, and small tiles with a page** (plan 2.6, 2026-11-05):
- **Page.** The input level (the default source's volume, empty while muted), the input devices as Settings > Sound
  lists them (PipeWire's audio nodes that are neither streams nor sinks), the one in use marked; a click sets
  `preferredDefaultAudioSource`, the same hint Settings > Sound gives. "Sound settings" opens that page.
- **Small tiles.** A dual-target tile opened its page from anywhere but its icon, and an icon-only tile is all icon,
  so one could not be switched at all: Microphone, icon-only by default, would have lost its mute. Now an icon-only
  tile toggles on a click, even when dual-target, and opens its page on a long press or a right click, as Android's
  small tiles do. Wide tiles are unchanged.

**D110. Settings: Connections; Do not disturb under Notifications; Dark theme as a switch** (plan 5.2, the
maintainer's list, 2026-11-05):
- **Connections.** The Network (Wi-Fi, Ethernet) and Bluetooth pages (D68) became one page, under an Airplane mode
  switch that works as Quick Settings' tile (on while every radio there is is off). The two views and backends are
  kept and loaded inside it by their files (Quickshell resolves a folder's types only where the root imports that
  folder, LESSONS). `network` and `bluetooth` still open it (`Pages.moved`), so links and `settings open` keep working.
- **Do not disturb** is shell state (state.json), not a setting, so Notifications has a small view of its own for it,
  under its sound setting.
- **Dark theme.** `style.mode` ("dark" or "light") shows as a switch titled Dark theme: a hint's `on`/`off` give a
  switch over a setting of two values, and a hint's `title` replaces the schema's. The schema is unchanged.

**D111. Ethernet ports switch off and on** (plan 5.2, the maintainer's request, 2026-11-05):
- Each port on Connections has a switch, as Wi-Fi. Off is Quickshell's `WiredDevice.disconnect()`, NetworkManager's
  device disconnect, which keeps the port down (no autoconnect) until it is asked again; on is the port's saved
  connection (`network.connect()`), or `nmcli device connect PORT` when Quickshell knows none. A port shows
  Connecting, Disconnecting, Connected, Off or No cable; off with no cable it cannot be switched on.
- Airplane mode stays radios only (Wi-Fi and Bluetooth), as GNOME, Windows, macOS, Android and ChromeOS have it:
  Ethernet is no radio, and the maintainer's machine is on Ethernet alone.
- **Not verified.** The real switch against NetworkManager: trying it on the maintainer's machine would cut its only
  connection. Only the page with a fake backend is tested, and the real backend is loaded by the smoke test.

**D112. Moving a desktop widget to another screen** (plan 4.4, 2026-11-05):
- Each screen keeps its own grid (D81), so a widget cannot be dragged across: edit mode's bar gets "Move to" (shown
  only with more than one screen, enabled with a widget selected), a menu of the other screens by model and output
  name. The widget goes in the first free cells there, as Add places one, at its size or smaller (the target grid's
  `fitNew`); a screen without room is greyed out. Its place on the old screen is not kept, and it keeps its id unless
  the other screen has that id already. Both screens are saved in one state write (`Desktop.withMoved`).
- IPC `widgets move ID SCREEN` does the same while editing (a screen's grid exists only while it shows widgets or
  they are edited, D31), false when it has no room or there is no such screen.
- Tested offscreen (the data, the button and menu), and in the real shell under headless sway with a second output
  plugged in (`create_output`). Not verified on two real monitors.

**D113. Brightness for every display: ddcutil beside brightnessctl** (plan 2.1, the maintainer's request,
2026-11-05):
- brightnessctl (D39) sets backlights only, so a desktop had no brightness at all. External monitors take it over
  DDC/CI (VCP feature 0x10), through ddcutil (new runtime dependency, approved): `ddcutil detect --terse` finds
  the monitors that answer (by I2C bus, with their DRM connector, which is niri's output name without the card),
  `getvcp 10 --brief --bus N` reads one (about 50 ms here), `setvcp 10 V --bus N --noverify` sets it (about 90 ms).
  It needs read and write access to /dev/i2c-* (the `i2c` group, NixOS's `hardware.i2c.enable`); the shell does
  not set that up, the system does.
- `BrightnessService.displays` lists every backlight (brightnessctl now lists all, `-l`) then every monitor that
  answered. `set()` sets them all to the same fraction and `value` is the first one's, so the one Quick Settings
  slider, the keys and the OSD work as before. Settings > Display has a slider per output: a monitor by its
  connector, a backlight under a built-in panel (eDP, LVDS, DSI).
- Writes go one at a time, each display keeping only its newest value, so a dragged slider never queues a process
  per frame. A read while a display's write runs or waits keeps the value shown for it. A monitor may go to 0 (its
  dimmest); a backlight never does (it can turn the panel off). Monitors are looked for at start and when screens
  change; values are read again when Quick Settings or Settings > Display opens.
- Tests use a fake ddcutil (tests/qs/bin) everywhere the shell steps brightness, so no real monitor is touched.
- **Not verified:** the shell setting the maintainer's monitor. Only the commands were tried by hand (a read, and
  writing its current value back); the shell's own writes ran against the fake.

**D114. A small dual-target tile colors as a plain one** (plan 2.6, fix to D109):
- An icon-only tile draws no separate icon target, but a dual-target one (Microphone) still took SystemUI's dual
  colors, which color the icon for that target: on, its icon was primaryOn over surfaceVariant, pale on pale. An
  icon-only tile now takes the plain active and inactive colors, as every other small tile.
