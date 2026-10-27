# Changelog

Releases are git tags pushed to https://github.com/randalthor17/rutile. Work after the latest tag is under
Unreleased and is on `main` there (or in an untagged `rutile-dev-<sha>.bundle` from a session that cannot push). Every tag must have a section here (a test checks).

## Unreleased

- **GTK, Qt and KDE apps in the shell's look** (`programs.rutile.theming.enable = true`, home-manager): GTK 3 and
  libadwaita apps, Qt apps and KDE apps (Dolphin, Kate) take the shell's colors, Google Sans Flex and the Adwaita
  icons; checked by screenshotting real apps (`make theming-check`). New switch in Settings: KDE apps
  (kdeglobals). See `docs/install.md`.
- **Fixes from the first real install:** the power menu (and every popup) is gone as soon as it has faded, not
  300 ms later, and popups now fade in as they open. `rutile-shell --help` explains the command and lists every
  call the shell answers (`rutile-shell lock lock`, `rutile-shell osd volumeUp`, ...). Colors in other apps now work
  before the first wallpaper (they take the shell's own colors) and pick up the first one; configs home-manager
  manages are left alone, and the log says what to add (`docs/install.md`).
- **niri in the shell's colors** (Settings > Wallpaper > Colors in other apps > niri, off at first): focus ring,
  borders, tab indicators and the overview's backdrop follow the wallpaper. The home-manager module includes the
  file; without it, add `include optional=true "rutile-colors.kdl"` to config.kdl.
- **On GitHub:** the repository is public at https://github.com/randalthor17/rutile, and the docs use its flake,
  `github:randalthor17/rutile`.
- **Install with Nix** (`docs/install.md`): the flake now has the shell as a package (`nix run`) and a
  home-manager module, `programs.rutile.enable = true`: the shell as a user service, the `rutile-shell` command,
  niri's blur rule for the power menu and password dialog, and keybinds if you want them
  (`programs.rutile.niri.binds.enable`).
- **The shell runs without Python**: the palette from the wallpaper and other apps' colors are done in the shell
  itself, and the Firefox colors' helper is a small C program (`make native`, or the flake's `pywalfox-host`).
- **Colors in other apps** (preliminary; Settings > Wallpaper & style): a main switch and one per app, all off
  until you turn them on. niri, GTK, Qt (qt5ct/qt6ct), kitty, Ghostty, btop, Neovim (`:colorscheme rutile`) and Firefox (install the
  Pywalfox extension; Rutile is its backend, no pywalfox program needed) follow the wallpaper's colors. Turning
  an app off puts its old look back. If Noctalia themes the same apps, turn that off there first.
- **Settings app** (plan 5.1): Quick Settings' gear (or `ipc call settings open <page>`) opens Settings, laid out
  like Googlebook's: search on the left above the pages, the page's settings on the right. Every setting so far is
  there: wallpaper colors, notification sounds, screen lock, the polkit agent, animation speed. Choose… on the
  wallpaper opens your desktop's file chooser (the portal; restart the shell once for it); the shelf's pins show
  their value for now. Settings set in Nix show a lock.
- **Password prompts** (plan 2.8): the shell is now the polkit agent, so `pkexec`, disk mounts and installs ask
  for your password in a card over the blurred desktop (Enter to send, Escape to cancel; a wrong password shakes).
  Run one agent per session: turn off another one (Noctalia's `polkit_agent`), or set `polkit.agent: false` to
  keep yours.
- **Dev shell**: `nix develop` now includes Python's `jsonschema`, so the widget checker's cross-check runs
  instead of skipping (D29; the checker itself still uses only the standard library).
- **Power menu** (plan 2.8): Quick Settings' power button now opens a full-screen menu over the blurred desktop:
  Lock, Sleep (new), Sign out, Restart, Shut down, as large round buttons. Arrow keys and Enter work; Escape or a
  click elsewhere closes it. `ipc call power toggle` from a keybind. On niri, add the layer rule in
  `docs/quick-settings.md` to blur your windows too, not only the wallpaper. The old dropdown is gone.
- **Wallpaper** (plan 2.9): the shell draws the wallpaper itself. `ipc call wallpaper set /path/to/image.png`
  (or `wallpaper.path` in settings.json) shows it on every screen with a crossfade, colors the shell from it
  (matugen; `wallpaper.palette: false` keeps the palette) and the lock screen blurs it. Turn off another
  wallpaper program (Noctalia's, swaybg) so they do not both draw.
- **Lock screen, polished** (plan 2.8): locking blurs the wallpaper in while the clock and password field rise into
  place; unlocking runs it back and the wallpaper sharpens before the desktop returns. The wallpaper is the new
  `wallpaper.path` setting. `loginctl lock-session` (and idle tools) now lock, the computer locks before it
  suspends (`lock.beforeSleep`, on by default) and after 10 minutes idle (`lock.idleMinutes`; 0 turns it off; a
  playing video keeps it unlocked).
- **Lock screen** (plan 2.8): Lock in Quick Settings' power menu, or `ipc call lock lock` from a keybind, covers
  every screen with the time, the date, your name and a password field, and only your password unlocks it (the
  system's `login` PAM service). A wrong one says so and the field shakes. Nothing unlocks it over IPC. If the
  shell crashes while locked, the screens stay locked and blank: that is how the protocol keeps the session safe.
- **Palette from the wallpaper**: `tools/palette.py render --image <wallpaper> --out ~/.cache/rutile/palette.json`
  colors the shell from the image's dominant color; the shell picks the new file up at once.
- **Fix:** a palette rendered while the shell ran without one was ignored until a restart; now it is picked up
  within a few seconds.
- **Toasts** (plan 2.8): short messages at the bottom left, one at a time, e.g. from a screenshot script:
  `ipc call toast send "Screenshot saved" photo_camera` (the icon may be ""). Each stays 4 s, longer while the
  pointer is on it; the same message again keeps it up instead of queueing. The shell can give one an action.
- **Fix:** `ipc call osd show` never worked from the command line (the CLI takes `show` for its own command); it
  is now `ipc call osd display volume`.
- **Notification sounds** (plan 2.8): a notification that pops up plays a sound through PipeWire's `pw-play`: the
  sound the app asks for, or the freedesktop sound theme's message sound. Apps can ask for silence; Do not disturb
  is silent except for critical ones, and a burst plays once. `notifications.sound` in settings.json turns it off.
- **Volume and brightness OSD** (plan 2.8): changing the volume (from any key or app) or the brightness (through
  `ipc call osd brightnessUp` and the other `osd` calls, for the media keys) shows the level at the bottom of the
  screen as Quick Settings' slider, which can be dragged. It goes after 1.5 s, not while the pointer is on it.
- **Clicks reach the whole panel** (fix): Clear all at the bottom of the notification list took no clicks, nor
  did the left and bottom edges of Quick Settings or the part of its power menu below the panel; clicks went
  to the window behind. The windows' click areas had been measured mid-opening, at 85% of the panel's size.
- **Clear all is animated** (plan 2.8): the notifications sweep off to the side one after another from the top,
  then the list closes up and "No notifications" fades in. One that arrives during the sweep stays.
- **Smoother notification motion** (plan 2.8): popups coming and going, and the list closing up or opening a
  group, no longer stutter. Their windows were resized on every frame of the motion; now they change size only
  when a notification comes or has gone (the list's not at all).
- **Notifications** (plan 2.8, first part, D47): the shell is now a notification server. Notifications pop up
  under the status pill on the screen you are using, newest on top, at most three: the app, when it came, the
  summary and text, a picture when the sender gives one, and its buttons; a click on the card does the app's
  default action, the close button dismisses it. They go after a few seconds (the sender's time, or 6 s), not
  while the pointer is over them; critical ones stay. `ipc call notifications setDnd true` turns on Do not
  disturb (only critical ones pop up). While another notification daemon runs (Noctalia, mako, dunst), it keeps
  the notifications and the shell waits; the shell takes over when it stops.
- **Notifications, more** (plan 2.8, D47): swipe a notification sideways to dismiss it; the list groups each
  app's notifications under its newest ("Show 2 more from Mail"), and a dismissed one fades out while the rest
  close up; apps that offer it (chat apps) get a Reply button with a field right in the notification. The dev
  shell has `notify-send` (libnotify) for trying it.
- **Notification list** (plan 2.8, D47): a bell left of the status pill shows whether there are notifications
  (a dot) or Do not disturb is on (crossed out). Clicking it opens the list under it: a Do not disturb switch,
  every notification newest first with its buttons and a close button, and Clear all. Opening it clears the
  popups; Escape or a click elsewhere closes it. `ipc call notifications toggle` does the same from a keybind.
- **Quick Settings in launcher search** (plan 2.7, maintainer's choice): typing "wifi", "dark", "mute" or
  "brightness" also finds the Quick Settings controls this system has, shown with their symbol and, in the list,
  their state. Choosing Wi-Fi, Bluetooth, Microphone, Dark theme or Airplane mode switches it at once; Brightness
  and Volume open Quick Settings. Apps rank ahead of a setting on an equal match, and a category chip shows apps
  only.
- **Launcher remembers what you use** (plan 2.7, D46): apps opened from the launcher rank higher in search,
  more so when used lately (kept in `~/.local/state/rutile/state.json`). The grid without a search stays in name
  order, so apps do not move around.
- **Pin and unpin from the launcher** (plan 2.7): the app menu has Pin to shelf or Unpin from shelf, saved in
  the `shelf.pins` setting. Not offered when the pins are set in Nix.
- **Saved settings** (plan 2.5, D45): the shell keeps its settings in `~/.config/rutile/settings.json` and what it
  remembers in `~/.local/state/rutile/state.json` (the XDG directories). The launcher's grid or list view and
  the animation speed (`ipc call motion setSpeed`) now survive a restart, and the shelf's pins are the
  `shelf.pins` setting (replacing `RUTILE_SHELF_PINS`). Editing the file applies at once; a file with a mistake
  is left alone and the last good values stay. Every setting is described in `settings/schema.json`.
- **Home-manager module** (`homeManagerModules.default`): `programs.rutile.settings.motion.speed = 1.5;` and the
  like, type-checked against the same schema, are written to `~/.config/rutile/managed.json`. Settings from Nix
  win over the shell's own and cannot be changed from the shell.
- **App menu in the launcher** (plan 2.7): right-click an app, or press the Menu key or Shift+F10 on the current
  one, for Open and the actions its desktop file lists (Firefox's New Private Window, say). The arrows and Enter
  work in it, Escape closes only the menu, and a click outside closes it without doing anything else. It uses the
  shared popup motion. The menu is a shared `Menu` component, which Quick Settings' power menu now uses too.
- **Launcher chips move** (maintainer's request): a filter chip's check mark grows in and out (the chip widens to
  make room; every filter chip, not only the launcher's), the chip row scrolls smoothly to the chosen chip, and
  the results fade and rise in when the chip or the grid/list view changes. All follow `Motion.speed` (D43).
- **Launcher chips and list view** (plan 2.7, maintainer's request): chips under the search field filter the
  apps by category (from the desktop files; only categories that have apps; Tab and Shift+Tab step through them),
  and a button in the search field switches between the grid and a list that shows each app's description. The
  choice holds until the shell restarts (saving it needs settings, plan 2.5). Search also matches a name's
  letters in order from a word start, so "nvi" finds Neovide as well as Neovim.
- **Launcher** (plan 2.7, first part): the shelf's launcher button, or `quickshell -p shell/shell.qml ipc call
  launcher toggle` from a niri keybind, opens a panel above the shelf: type to search the installed apps (ranked
  by a port of DankMaterialShell's scorer, typos included), arrows to move, Enter to open, Escape to close.
- **Smaller shelf** (maintainer's request): 48 px tall with 32 px icons in 40 px buttons (was 56, 40 and 48).
- **The shelf shows windows by workspace** (D44, maintainer's request, as Noctalia does): after the pinned apps,
  each workspace on that screen gets a capsule with its number and one icon per window in layout order; the
  active workspace is tinted and the focused window marked, and a click focuses that window. Pinned apps start
  the app. The wheel over the shelf moves to the previous or next workspace on that screen; past the last one is
  niri's blank workspace, shown as an empty numbered capsule. The data comes from niri's IPC socket
  (`NiriService`, Quickshell's `Socket`); other compositors get the windows in one group.
- **Fix:** `make check` let qmllint warnings through (qmllint exits 0 on some); two had slipped in and are fixed.
- **Shelf** (plan 2.4, first part): a bar along the bottom of every screen that keeps windows above it, with a
  launcher button (does nothing until the launcher, plan 2.7), pinned apps (the first installed file manager,
  browser and terminal, or `RUTILE_SHELF_PINS=id,id`) that start on click, and running apps from the compositor
  (a dot; a longer primary dash while active; a click brings the next window forward). Apps that run without
  being pinned follow a divider. Apps without an icon show their initial.
- **Power actions wait for Quick Settings to close** (maintainer's request): choosing Lock, Sign out, Restart or
  Shut down closes the menu and the panel first, and runs the action once they have gone; reopening the panel
  before then cancels it.
- **One popup motion, one animation speed** (D43, maintainer's rule): every popup, dropdown and menu grows and
  fades in from where it opens and plays it backwards on close (`PopupMotion`, `PopupLoader`); the power menu
  now does, and the power button's chevron turns. Every animation follows `Motion.speed`: start the shell with
  `RUTILE_ANIMATION_SPEED=0.5` (or 2, or 0 for no motion), or change it live with
  `quickshell -p shell/shell.qml ipc call motion setSpeed 2`. The lint rejects animations that would ignore it.
- **Quick Settings opens and closes with motion** (maintainer's request): the panel grows in from the corner
  under the status pill on the spatial spring and fades in; closing (pill, Escape, focus leaving, IPC) shrinks and
  fades it before the window is unloaded. Opening again mid-close grows it back.
- **Power menu** (maintainer's request): the power button (power icon and chevron, as Googlebook) opens a menu
  with Lock, Sign out, Restart and Shut down (`loginctl`, niri, `systemctl`). A full-screen power menu over a
  blurred desktop is planned to replace it (plan 2.8).
- **Fix** (maintainer's report): the power menu was cut off at the bottom when the panel is short (no brightness
  row). The window now grows to fit the menu, and its mask keeps the extra space click-through.
- **Clock** (plan 2.3): every screen shows the time and date at the top left ("8:55  Fri, Oct 9"), on the same
  tonal container as the status pill; 24-hour when the locale uses it. The Wayland smoke test checks that it
  shows the current time.
- **Scroll the volume on the status pill** (maintainer's request): scrolling over the pill's volume glyph
  changes the volume by 5% a notch, without opening Quick Settings. Muted counts as 0: scrolling up unmutes from
  the bottom. The other glyphs and a click behave as before.
- **Fix** (maintainer's report): scrolling the pill's volume did nothing on niri. Qt reports the wheel there as a
  touchpad, and the wheel handler accepted only mice.
- **The top edge stays visible; windows keep clear of it** (D42, maintainer's design): the status pill is back
  on the top layer, and each screen reserves 32 px at the top through a 1 px transparent, click-through layer
  surface with an exclusive zone (as DankMaterialShell and Caelestia do), so windows are laid out below the pill
  with niri's gap. The Wayland smoke test checks that sway's workspace starts below the reserved space.
- **Status pill on the desktop layer, with a container** (maintainer's requests): the pill now sits on layer
  shell's bottom layer, above the wallpaper and below windows, and always has a tonal container
  (`surfaceContainer`). Ethernet shows Android's `settings_ethernet` icon (Material Symbols has no RJ45 jack), and
  Quick Settings' edit-tiles button is a pen (`edit`). `ipc call quicksettings state` reports the pill's layer.
- **Fix** (maintainer's report): pressing the volume slider closed Quick Settings. The panel closed when its own
  item lost focus, and a click gives focus to the slider inside it; it now closes only when its window loses
  keyboard focus. A test clicks a slider and a tile inside the panel.
- **The status pill is smaller** (maintainer's report): 24 px tall with 16 px icons sitting on the wallpaper, as
  in the Googlebook screenshots; it gets its container only while Quick Settings is open.
- **Status pill** (plan 2.3, D41): a pill at the top right of every screen shows the network (Wi-Fi strength or
  cable), volume and battery, and opens Quick Settings below it on that screen; it is marked while the panel is
  open. Quick Settings now closes when keyboard focus leaves it (a click into a window), as well as on Escape.
  `quickshell -p shell/shell.qml ipc call quicksettings state` reports what the windows see.
- **Fix:** the real shell's panel had no backend: `backend: backend` inside a window binds the window's own
  property to itself, so the panel showed no brightness and could not have changed anything. Found while adding
  the pill; the Wayland smoke test now checks the wiring through `state`.
- **Fix:** the panel asked its backend to refresh before the backend arrived (a TypeError in the log).
- **Quick Settings, in the real shell** (plans 2.1 and 2.6a, D39, D40): `shell/shell.qml` is the shell's entry
  point. `quickshell -p shell/shell.qml ipc call quicksettings toggle` opens Googlebook's Quick Settings at the
  top right: edit-tiles, settings and power buttons; brightness (through brightnessctl, a new runtime
  dependency) and volume sliders; Wi-Fi, Bluetooth, Microphone, Dark theme and Airplane mode tiles on Quickshell's
  Networking, Bluetooth and Pipewire services; and "Edit tiles". The window exists only while open. The panel is
  tested offscreen against a fake backend and shown in the gallery; the real shell is tested under a headless
  sway (`tools/qtws.py test-wayland`, with a screenshot option), and the brightness service against a fake
  brightnessctl. The dev shell gains brightnessctl, and sway and grim for tests.
- **Fix:** the brightness service announced itself available before it knew its device, so a control reacting
  at once would have set the backlight to its minimum. Found by its test.
- **Decision D38** (maintainer): plan 2.2 waits for Quickshell's `Quickshell.Niri` module (PR #949) instead of
  building Quickshell from git or using `Quickshell.WindowManager` (ext-workspace-v1, immature on niri); the
  fallback is named. niri supports `ext-background-effect-v1`, so the shell's own surfaces may blur
  (`BackgroundEffect`), superseding D4's no-blur part.
- **Quickshell first** (maintainer's rule, plan H5): `docs/HANDOFF.md` now says to check the Quickshell docs for
  the installed version (0.3.2) before building anything, with a table mapping its types to plan items, and the
  plan names the types for each Phase 2 item. Code that needs Quickshell types can now be tested:
  `tools/qtws.py test-qs` runs `tests/qs/tst_*.qml` as shells under `quickshell`, offscreen, and `make check`
  runs it. `PaletteWatcher`, untested until now, is covered (load, reload when the file changes, missing file).
  The components stay plain QtQuick: Quickshell has no controls to replace them.
- **ShapeMorph and the M3 Expressive shape library** (plan 1.5f, D37): `ShapeMorph { shape: "cookie9Sided" }`
  draws any of the 35 shapes of Compose's `MaterialShapes` (circle, cookies, bursts, clovers, pixel shapes,
  heart and the rest), and changing `shape` morphs to the new one on the fast spatial spring. The shape
  definitions are parsed from the vendored `MaterialShapes.kt`; rounding, normalizing and morphing are ported
  from androidx graphics-shapes (vendored for review) into `shell/common/ShapeMath.js`, and checked against an
  independent Python port (`tests/shape_ref.py`). The gallery shows every shape and a morph you can click
  through. A shape costs 47 KiB (circle) to 418 KiB (the 192-curve soft boom).
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
