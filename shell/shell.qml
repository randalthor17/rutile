// Rutile Shell. Run with:   quickshell -p shell/shell.qml
// Open Quick Settings from a niri keybind:   quickshell -p <path>/shell/shell.qml ipc call quicksettings toggle
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.quicksettings

ShellRoot {
    PaletteWatcher {}

    LazyLoader {
        id: quickSettings
        QuickSettingsWindow {
            onCloseRequested: quickSettings.active = false
        }
    }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void { quickSettings.active = !quickSettings.active; }
        function open(): void { quickSettings.active = true; }
        function close(): void { quickSettings.active = false; }
        function isOpen(): bool { return quickSettings.active; }
    }
}
