# Quick Settings (plan 2.6)

The first piece of the real shell. `shell/shell.qml` is the shell's entry point; today it runs the palette
watcher and Quick Settings.

```
quickshell -p shell/shell.qml                                          # run the shell
quickshell -p shell/shell.qml ipc call quicksettings toggle            # open or close Quick Settings
```

The shell shows a status pill at the top right of every screen (network, volume, battery); clicking it opens
Quick Settings below it on that screen, and clicking it again closes it. `qs -p shell` works the same from the
repo root. `quicksettings` also has `open`, `close`, `isOpen` and `state` (JSON of what the windows see: open,
whether the panel and pills reached the backend, whether brightness shows, which pill is marked open, the pills'
layer and the space reserved per screen). A niri keybind runs the `toggle` line (with the
absolute path), e.g. `Mod+S { spawn "quickshell" "-p" "/path/to/shell/shell.qml" "ipc" "call" "quicksettings" "toggle"; }`.
Escape closes the panel, and so does the panel's window losing keyboard focus, e.g. by clicking into a window
(D41); clicks inside the panel do not.
Clicking empty desktop or another program's bar does not close it: those clicks do not move focus on niri.

## How it is built

| File | Needs Quickshell | What it does |
|---|---|---|
| `shell/shell.qml` | yes | `ShellRoot`, `PaletteWatcher`, the one backend, a status pill per screen (`Variants`), a `LazyLoader` with the Quick Settings window, the `IpcHandler` |
| `shell/bar/ScreenStatus.qml` | yes | one screen's top edge: the pill's window and the space it reserves |
| `shell/bar/StatusWindow.qml` | yes | the pill's `PanelWindow` at the top right of one screen, on the top layer: always visible |
| `shell/bar/EdgeExclusion.qml` | yes | a 1 px transparent, click-through surface whose exclusive zone keeps windows below the pill (32 px; niri adds its gap) (D42) |
| `shell/bar/StatusPill.qml` | no | network, volume and battery icons (one `Icon` with three ligatures) and the battery percentage, 24 px tall with 16 px icons on a tonal container (`surfaceContainer`; `secondaryContainer` while Quick Settings is open). Ethernet is `settings_ethernet`, Android's icon: Material Symbols has no RJ45 jack |
| `shell/bar/StatusIcons.js` | no | which Material Symbol for which state |
| `shell/quicksettings/QuickSettingsWindow.qml` | yes | a `PanelWindow` (layer shell) at the top right, `ExclusionMode.Ignore`, keyboard focus for Escape |
| `shell/quicksettings/QuickSettingsBackend.qml` | yes (through `qs.services`) | the panel's backend interface on top of the services |
| `shell/quicksettings/QuickSettingsPanel.qml` | no | header, brightness and volume sliders, tiles on the `EditableGrid` |
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
- Power menu, settings and sound settings buttons only emit signals: nothing opens yet.
- More tiles: Do not disturb (needs the notification server, 2.8), Night light, Power saver (`PowerProfiles`,
  needs power-profiles-daemon and a way to tell it is missing).
- **Not verified:** clicking the pill on a real screen (only its signal is tested offscreen, and the IPC path
  live), several screens; the setters (Wi-Fi, Bluetooth, volume, microphone, brightness) have not run against real
  hardware; Wi-Fi, Bluetooth and a backlight have not been seen working at all (the machine it ran on has none
  of them active).
