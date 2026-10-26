# Quick Settings (plan 2.6)

The first piece of the real shell. `shell/shell.qml` is the shell's entry point; today it runs the palette
watcher and Quick Settings.

```
quickshell -p shell/shell.qml                                          # run the shell
quickshell -p shell/shell.qml ipc call quicksettings toggle            # open or close Quick Settings
```

`quicksettings` also has `open`, `close` and `isOpen`. A niri keybind runs the `toggle` line (with the
absolute path), e.g. `Mod+S { spawn "quickshell" "-p" "/path/to/shell/shell.qml" "ipc" "call" "quicksettings" "toggle"; }`.
Escape closes the panel.

## How it is built

| File | Needs Quickshell | What it does |
|---|---|---|
| `shell/shell.qml` | yes | `ShellRoot`, `PaletteWatcher`, a `LazyLoader` with the window, the `IpcHandler` |
| `shell/quicksettings/QuickSettingsWindow.qml` | yes | a `PanelWindow` (layer shell) at the top right, `ExclusionMode.Ignore`, keyboard focus for Escape |
| `shell/quicksettings/QuickSettingsBackend.qml` | yes (through `qs.services`) | the panel's backend interface on top of the services |
| `shell/quicksettings/QuickSettingsPanel.qml` | no | header, brightness and volume sliders, tiles on the `EditableGrid` |
| `shell/services/AudioService.qml` | yes | default output and input: volume, mute (`Pipewire`, `PwObjectTracker`) |
| `shell/services/NetworkService.qml` | yes | Wi-Fi on/off, connected network (`Networking`, NetworkManager) |
| `shell/services/BluetoothService.qml` | yes | adapter on/off, a connected device (`Bluetooth`, BlueZ) |
| `shell/services/BrightnessService.qml` | yes | backlight through `brightnessctl` (D39) |

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
services remains.

## Tests

- `tests/qml/tst_quick_settings.qml` (offscreen, `make check`): the panel against a fake backend, every tile,
  slider, button and edit mode; brightnessctl output parsing.
- `tests/qs/tst_brightness_*.qml` (`tools/qtws.py test-qs`, in `make check`): the brightness service against a fake
  `brightnessctl` (`tests/qs/bin/`), including how quick changes are queued.
- `tools/qtws.py test-wayland [--screenshot FILE]` (in `make check` when sway is installed): the real
  `shell/shell.qml` under a headless sway with its own runtime directory, opened and closed over IPC, failing on
  any QML error or warning (D40). There is no PipeWire or session there, and brightness is the fake, so it
  cannot change the machine's settings.

## Not done yet

- Closing on a click outside the panel; per-tile detail pages (Wi-Fi networks, Bluetooth devices); the
  available-tiles list in edit mode; saving the tile layout and the dark theme (plan 2.5).
- Blur behind the panel (`BackgroundEffect`, D38): the panel is opaque like Googlebook's for now.
- Power menu, settings and sound settings buttons only emit signals: nothing opens yet.
- More tiles: Do not disturb (needs the notification server, 2.8), Night light, Power saver (`PowerProfiles`,
  needs power-profiles-daemon and a way to tell it is missing).
- **Not verified:** any of it on the maintainer's machine in niri, with real Wi-Fi, Bluetooth, PipeWire and a
  backlight. The services were only loaded where those daemons were missing; their setters have not run.
