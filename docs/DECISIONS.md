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
