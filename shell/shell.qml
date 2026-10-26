// Rutile Shell. Run with:   quickshell -p shell/shell.qml   (or `qs -p shell`)
// A clock sits at the top left of every screen, a status pill at the top right and the shelf along the bottom; clicking it opens Quick Settings on that screen.
// From a niri keybind:   quickshell -p <path>/shell/shell.qml ipc call quicksettings toggle
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.bar
import qs.launcher
import qs.quicksettings
import qs.shelf

ShellRoot {
    id: shell

    // The screen Quick Settings opens on; null lets the compositor choose (the focused output on niri).
    property var quickSettingsScreen: null

    // Open, and not on its way out: a closing panel plays its motion before the loader drops it.
    readonly property bool quickSettingsOpen: quickSettings.active && !(quickSettings.item?.closing ?? false)

    function closeQuickSettings() {
        if (quickSettings.item) quickSettings.item.close();
        else quickSettings.active = false;
    }

    // The launcher, as Quick Settings: open on a screen (null: the compositor's choice), closing plays its motion.
    property var launcherScreen: null
    property bool launcherListView: false
    readonly property bool launcherOpen: launcher.active && !(launcher.item?.closing ?? false)
    function closeLauncher() {
        if (launcher.item) launcher.item.close();
        else launcher.active = false;
    }
    function toggleLauncher(screen) {
        const here = screen === null || screen === launcherScreen;
        if (launcherOpen && here) {
            closeLauncher();
            return;
        }
        if (launcher.item?.closing && here) {
            launcher.item.reopen();
            return;
        }
        launcher.active = false;
        launcherScreen = screen;
        launcher.active = true;
    }

    function toggleQuickSettings(screen) {
        const here = screen === null || screen === quickSettingsScreen;
        if (quickSettingsOpen && here) {
            closeQuickSettings();
            return;
        }
        if (quickSettings.item?.closing && here) {
            quickSettings.item.reopen();        // reopened mid-close: it grows back from where it is
            return;
        }
        quickSettings.active = false;
        quickSettingsScreen = screen;
        quickSettings.active = true;
    }

    PaletteWatcher {}

    // The animation speed (D43): RUTILE_ANIMATION_SPEED=0.5 halves it, 0 turns motion off; `ipc call motion
    // setSpeed 2` changes it live. Saved with the other settings once plan 2.5 lands.
    Component.onCompleted: {
        const speed = parseFloat(Quickshell.env("RUTILE_ANIMATION_SPEED"));
        if (speed >= 0) Motion.speed = speed;
    }
    IpcHandler {
        target: "motion"
        function setSpeed(speed: real): void { Motion.speed = Math.max(0, speed); }
        function speed(): real { return Motion.speed; }
    }

    // Not named `backend`: inside a window, `backend: backend` would bind the property to itself.
    QuickSettingsBackend { id: shellBackend }

    Variants {
        id: statusWindows
        model: Quickshell.screens
        ScreenStatus {
            required property var modelData
            screen: modelData
            backend: shellBackend
            // the screen the panel is on, also when the compositor chose it (opened over IPC)
            open: shell.quickSettingsOpen && quickSettings.item?.screen === modelData
            onClicked: shell.toggleQuickSettings(modelData)
        }
    }

    ShelfBackend { id: shelfBackend }

    Variants {
        id: shelves
        model: Quickshell.screens
        ShelfWindow {
            required property var modelData
            screen: modelData
            backend: shelfBackend
            onLauncherClicked: shell.toggleLauncher(modelData)
        }
    }

    LazyLoader {
        id: launcher
        LauncherWindow {
            screen: shell.launcherScreen
            // grid or list stays as last chosen until the shell restarts (saved settings: plan 2.5)
            listView: shell.launcherListView
            onListViewChanged: shell.launcherListView = listView
            onCloseRequested: launcher.active = false
        }
    }

    // From a niri keybind: quickshell -p <path>/shell/shell.qml ipc call launcher toggle
    IpcHandler {
        target: "launcher"
        function toggle(): void { shell.toggleLauncher(null); }
        function open(): void { if (!shell.launcherOpen) shell.toggleLauncher(null); }
        function close(): void { shell.closeLauncher(); }
        function isOpen(): bool { return shell.launcherOpen; }
        // Type a query into the open launcher; returns the first results' ids (diagnostics, the smoke test).
        function search(query: string): string {
            const p = launcher.item?.panel;
            if (!p) return "";
            p.query = query;
            return p.results.slice(0, 5).map(a => a.id).join(",");
        }
        // Show the launcher's apps as a list (true) or a grid; it stays so until the shell restarts.
        function setListView(list: bool): void { shell.launcherListView = list; }
        // Choose a category chip ("" is All) in the open launcher; returns the first results' ids.
        function category(id: string): string {
            const p = launcher.item?.panel;
            if (!p) return "";
            p.category = id;
            return p.results.slice(0, 5).map(a => a.id).join(",");
        }
        function state(): string {
            return JSON.stringify({ open: shell.launcherOpen, loaded: launcher.active,
                                    apps: launcher.item?.panel.apps.length ?? 0, listView: shell.launcherListView,
                                    categories: (launcher.item?.panel.categories ?? []).map(c => c.id) });
        }
    }

    LazyLoader {
        id: quickSettings
        QuickSettingsWindow {
            screen: shell.quickSettingsScreen
            backend: shellBackend
            onCloseRequested: quickSettings.active = false
        }
    }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void { shell.toggleQuickSettings(null); }
        function open(): void { if (!shell.quickSettingsOpen) shell.toggleQuickSettings(null); }
        function close(): void { shell.closeQuickSettings(); }
        function isOpen(): bool { return shell.quickSettingsOpen; }
        // What the windows see, as JSON: for diagnostics and tools/qtws.py test-wayland.
        function state(): string {
            const w = quickSettings.item;
            return JSON.stringify({
                open: shell.quickSettingsOpen,
                loaded: quickSettings.active,
                panelHasBackend: !!w && w.panelHasBackend,
                brightnessShown: !!w && w.brightnessShown,
                pillsOpen: statusWindows.instances.map(s => s.pill.open),
                pillsHaveBackend: statusWindows.instances.map(s => !!s.pill.backend),
                pillsOnTop: statusWindows.instances.map(s => s.pill.WlrLayershell.layer === WlrLayer.Top),
                reserved: statusWindows.instances.map(s => s.reserved),
                clocks: statusWindows.instances.map(s => s.clock.pill.timeText + " " + s.clock.pill.dateText),
                shelves: shelves.instances.map(s => ({ pinned: s.shelf.pinned.map(p => p.id),
                                                       workspaces: s.shelf.groups.map(g => [g.idx].concat(g.windows.map(w => w.appId))) }))
            });
        }
    }
}
