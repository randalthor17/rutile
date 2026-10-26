# Quick Settings (plan 2.6)

The first piece of the real shell. `shell/shell.qml` is the shell's entry point; today it runs the palette
watcher and Quick Settings.

```
quickshell -p shell/shell.qml                                          # run the shell
quickshell -p shell/shell.qml ipc call quicksettings toggle            # open or close Quick Settings
```

The shell shows a status pill at the top right of every screen (network, volume, battery); clicking it opens
Quick Settings below it on that screen, and clicking it again closes it. Scrolling
over its volume glyph changes the volume by 5% a notch without opening anything. `qs -p shell` works the same from the
repo root. `quicksettings` also has `open`, `close`, `isOpen` and `state` (JSON of what the windows see: open,
whether the panel and pills reached the backend, whether brightness shows, which pill is marked open, the pills'
layer, the space reserved per screen and the clocks' text). The launcher works the same way: `ipc call launcher toggle`, `open`, `close`, `isOpen`, `state`, and
`search <query>` (types into the open launcher, returns the best ids), `category <id>` (chooses a chip, `""` for
All, returns the best ids), `setListView <true|false>`, `actions <appId>` (the desktop actions it found) and
`chooseAction <appId> <actionId>` (runs one as the app menu would), `launch <id>` (an app or a setting such as
`qs:dark`) and `togglePin <appId>`. Notifications (D47): `ipc call notifications toggle` opens or closes the list
under the bell, `isOpen`, `setDnd <true|false>`, `dnd`, `dismiss <id>`, `dismissAll`, `invoke <id> <action>` and
`state` (what is kept and popping up, the windows, each screen's bell). A niri keybind runs the `toggle` line (with the
absolute path), e.g. `Mod+S { spawn "quickshell" "-p" "/path/to/shell/shell.qml" "ipc" "call" "quicksettings" "toggle"; }`.
Escape closes the panel, and so does the panel's window losing keyboard focus, e.g. by clicking into a window
(D41); clicks inside the panel do not. The panel grows in from the corner under the pill (`PopupMotion`, the motion
every popup shares, D43) and fades in; closing shrinks and fades it, and the window is unloaded once the motion ends (`isOpen` turns false
at once; opening again mid-close grows it back).

The power button at the panel's top right (the power icon and a chevron, as Googlebook) opens a menu: Lock
(`loginctl lock-session`), Sign out (`niri msg action quit --skip-confirmation`), Restart (`systemctl reboot`)
and Shut down (`systemctl poweroff`), from `shell/quicksettings/PowerActions.js`. A choice closes the menu and the
panel first and runs once the panel has gone (no confirmation, as Googlebook), so a lock screen or shutdown never
shows it; opening the panel again before then cancels it. The menu opens with the same popup motion from under the
button, and the chevron turns to point up while it is open.
Clicking empty desktop or another program's bar does not close it: those clicks do not move focus on niri.

A clock pill sits at the top left of every screen: the time and date ("8:55  Fri, Oct 9"; 12-hour without AM/PM
as Googlebook shows it, or 24-hour when the locale's short time format is), from Quickshell's `SystemClock`.
Googlebook draws it straight on the wallpaper; Rutile gives it the status pill's tonal container so it reads on
any wallpaper (the maintainer asked for a colored pill). It does nothing on click yet.

## How it is built

| File | Needs Quickshell | What it does |
|---|---|---|
| `shell/shell.qml` | yes | `ShellRoot`, `PaletteWatcher`, the one backend, a status pill per screen (`Variants`), a `LazyLoader` with the Quick Settings window, the `IpcHandler` |
| `shell/bar/ScreenStatus.qml` | yes | one screen's top edge: the clock's and the pill's windows and the space they reserve |
| `shell/bar/ClockWindow.qml` | yes | the clock's `PanelWindow` at the top left, top layer, with a `SystemClock` ticking each minute |
| `shell/bar/ClockPill.qml` | no | the time and date in one `Text` on the pill's container (`now` passed in, so tests use fixed dates) |
| `shell/bar/ClockText.js` | no | the time ("8:55", "20:55") and date ("Fri, Oct 9") strings, and whether a locale uses a 24-hour clock |
| `shell/bar/StatusWindow.qml` | yes | the pill's `PanelWindow` at the top right of one screen, on the top layer: always visible |
| `shell/bar/EdgeExclusion.qml` | yes | a 1 px transparent, click-through surface whose exclusive zone keeps windows below the pill (32 px; niri adds its gap) (D42) |
| `shell/bar/StatusPill.qml` | no | network, volume and battery icons (one `Icon` with three ligatures) and the battery percentage, 24 px tall with 16 px icons on a tonal container (`surfaceContainer`; `secondaryContainer` while Quick Settings is open). Ethernet is `settings_ethernet`, Android's icon: Material Symbols has no RJ45 jack |
| `shell/bar/StatusIcons.js` | no | which Material Symbol for which state |
| `shell/quicksettings/QuickSettingsWindow.qml` | yes | a `PanelWindow` (layer shell) at the top right, `ExclusionMode.Ignore`, keyboard focus for Escape |
| `shell/quicksettings/QuickSettingsBackend.qml` | yes (through `qs.services`) | the panel's backend interface on top of the services |
| `shell/quicksettings/QuickSettingsPanel.qml` | no | header, brightness and volume sliders, tiles on the `EditableGrid`, the open and close motion |
| `shell/quicksettings/Controls.js` | no | the tiles' names, icons and search words, their state from the backend, what a toggle asks; the same controls as launcher search results (choosing a toggle flips it, a slider opens Quick Settings) |
| `shell/quicksettings/PowerMenu.qml` | no | the power menu: a segmented list of `ListItem`s, created only while open |
| `shell/quicksettings/PowerActions.js` | no | the power menu's entries and their commands (run by the backend with `Quickshell.execDetached`) |
| `shell/services/AudioService.qml` | yes | default output and input: volume, mute (`Pipewire`, `PwObjectTracker`) |
| `shell/services/NetworkService.qml` | yes | Wi-Fi on/off, connected network (`Networking`, NetworkManager) |
| `shell/services/BluetoothService.qml` | yes | adapter on/off, a connected device (`Bluetooth`, BlueZ) |
| `shell/services/BrightnessService.qml` | yes | backlight through `brightnessctl` (D39) |
| `shell/services/PowerService.qml` | yes | the laptop battery (`UPower` display device) |

The window exists only while open: closing destroys it (D31). The panel shows and changes everything
through its `backend` (the interface is listed at the top of `QuickSettingsPanel.qml`), so the same panel runs
offscreen in the tests and in the gallery with a fake. Its tiles are controlled (D33): a toggle asks the
backend and the tile changes when the system does. The sliders follow the backend except while dragged.

Tiles: Wi-Fi and Bluetooth (large, dual target: the icon toggles, the body emits `detailsRequested`),
Microphone (mute), Dark theme, Airplane mode (on when every radio that exists is off; turning it off turns
Wi-Fi and Bluetooth on). Missing hardware makes a tile unavailable; a missing backlight or audio output hides
its slider. "Edit tiles" (the header's first button) removes and rearranges tiles; the result is reported
by `tilesEdited(tiles)` and kept in memory until settings persistence (plan 2.5).

Memory: an open panel is about 1.4 MiB (5 tiles, 2 sliders, the grid, 4 icon buttons); closed, nothing but the
services and the pills remains. A pill is 58 KiB (one `Icon` for all its symbols, no container while closed; the first version was 123).

To check a change in the live niri session: start the shell, `ipc call quicksettings open`, then
`niri msg action screenshot-screen -p false --path FILE` (niri's own screenshot; it also copies to the clipboard).
First run on the maintainer's niri (October 2026): the panel opened at the top right, volume followed PipeWire;
Wi-Fi and Bluetooth showed unavailable on that machine (no Wi-Fi device reported, BlueZ not running). With the
pill: it showed the wired network and volume and was marked while the panel was open, and moving focus to a
window (`niri msg action focus-column-right`) closed the panel.

## Tests

- `tests/qml/tst_quick_settings.qml` (offscreen, `make check`): the panel against a fake backend, every tile,
  slider, button and edit mode; brightnessctl output parsing.
- `tests/qs/tst_brightness_*.qml` (`tools/qtws.py test-qs`, in `make check`): the brightness service against a fake
  `brightnessctl` (`tests/qs/bin/`), including how quick changes are queued.
- `tools/qtws.py test-wayland [--screenshot FILE]` (in `make check` when sway is installed): the real
  `shell/shell.qml` under a headless sway with its own runtime directory, opened and closed over IPC, checking
  `state` (the panel and the pill reached the backend, brightness shows, the pill is marked and on the top layer,
  32 px reserved), that sway's workspace really starts 32 px down, and failing on any
  QML error or warning (D40). Headless sway has no pointer, so clicking the pill is not tested there (a
  `wlrctl` virtual pointer exists only for one command, too briefly for the shell to bind it). There is no PipeWire or session there, and brightness is the fake, so it
  cannot change the machine's settings.

## Not done yet

- Closing on a click on empty desktop or another bar (D41); per-tile detail pages (Wi-Fi networks, Bluetooth devices); the
  available-tiles list in edit mode; saving the tile layout and the dark theme (plan 2.5).
- Blur behind the panel (`BackgroundEffect`, D38): the panel is opaque like Googlebook's for now.
- Settings and sound settings buttons only emit signals: nothing opens yet.
- The power menu is a small dropdown for now. Planned (maintainer's request): a full-screen power menu over the
  blurred desktop, replacing it (plan 2.8). Lock runs `loginctl lock-session`, which locks nothing until a lock
  screen listens (plan 2.8) or e.g. swayidle runs one. Clicking elsewhere in the panel does not close the menu.
- More tiles: Do not disturb (needs the notification server, 2.8), Night light, Power saver (`PowerProfiles`,
  needs power-profiles-daemon and a way to tell it is missing).
- **Not verified:** clicking or scrolling the pill on a real screen (only its signal is tested offscreen, and the IPC path
  live), several screens; the setters (Wi-Fi, Bluetooth, volume, microphone, brightness) have not run against real
  hardware; Wi-Fi, Bluetooth and a backlight have not been seen working at all (the machine it ran on has none
  of them active).
