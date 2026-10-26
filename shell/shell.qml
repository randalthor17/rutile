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
import qs.notifications
import qs.quicksettings
import qs.services
import qs.shelf
import "quicksettings/Controls.js" as Controls

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
    // grid or list, as last chosen (remembered in state.json, D45)
    readonly property bool launcherListView: Settings.stateValue("launcher.view", "grid") === "list"
    function setLauncherListView(list) {
        Settings.setState("launcher.view", list ? "list" : "grid");
    }
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

    // The notification list (D47), as Quick Settings: on a screen (null: the compositor's choice).
    property var notificationListScreen: null
    readonly property bool notificationListOpen: notificationList.active && !(notificationList.item?.closing ?? false)
    function closeNotificationList() {
        if (notificationList.item) notificationList.item.close();
        else notificationList.active = false;
    }
    function toggleNotificationList(screen) {
        const here = screen === null || screen === notificationListScreen;
        if (notificationListOpen && here) {
            closeNotificationList();
            return;
        }
        if (notificationList.item?.closing && here) {
            notificationList.item.reopen();
            return;
        }
        notificationList.active = false;
        notificationListScreen = screen;
        notificationList.active = true;
        NotificationService.endPopups();        // they are in the list now
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

    // The animation speed (D43) is the motion.speed setting (D45). RUTILE_ANIMATION_SPEED overrides it for this
    // run (0.5 halves it, 0 turns motion off) until `ipc call motion setSpeed 2` saves a new speed.
    readonly property real envSpeed: parseFloat(Quickshell.env("RUTILE_ANIMATION_SPEED"))
    property bool speedFromEnv: envSpeed >= 0
    Binding {
        target: Motion
        property: "speed"
        value: shell.speedFromEnv ? shell.envSpeed : Settings.value("motion.speed")
    }
    IpcHandler {
        target: "motion"
        // false when the speed is out of range (0 to 4) or set in Nix
        function setSpeed(speed: real): bool {
            if (!Settings.set("motion.speed", speed)) return false;
            shell.speedFromEnv = false;
            return true;
        }
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
            notificationsOpen: shell.notificationListOpen && notificationList.item?.screen === modelData
            onClicked: shell.toggleQuickSettings(modelData)
            onBellClicked: shell.toggleNotificationList(modelData)
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
            listView: shell.launcherListView
            onListViewChanged: shell.setLauncherListView(listView)
            pinnedIds: shelfBackend.pinnedIds
            pinsEditable: shelfBackend.pinsEditable
            onPinToggled: app => shelfBackend.togglePin(app.id)
            // Quick Settings' controls as search results: a toggle flips, a slider opens Quick Settings
            settings: Controls.searchItems(shellBackend)
            onSettingChosen: item => {
                if (Controls.choose(item, shellBackend) === "open" && !shell.quickSettingsOpen)
                    shell.toggleQuickSettings(shell.launcherScreen);
            }
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
        // An app's desktop actions as the open launcher knows them, and choosing one as its menu would (the smoke test).
        function actions(appId: string): string {
            const app = launcher.item?.panel.apps.find(a => a.id === appId);
            return app ? app.actions.map(a => a.id).join(",") : "";
        }
        function chooseAction(appId: string, actionId: string): bool {
            const p = launcher.item?.panel;
            const app = p?.apps.find(a => a.id === appId);
            if (!app) return false;
            p.actionChosen(app, actionId);
            return true;
        }
        // Open an app, or choose a setting ("qs:dark"), as a click in the open launcher would (the smoke test).
        function launch(id: string): bool {
            const p = launcher.item?.panel;
            const item = p?.apps.concat(p.settings).find(a => a.id === id);
            if (!item) return false;
            p.choose(item);
            return true;
        }
        // Pin or unpin an app as its menu in the open launcher would; false when the pins are set in Nix.
        function togglePin(appId: string): bool {
            const p = launcher.item?.panel;
            const app = p?.apps.find(a => a.id === appId);
            if (!app || !p.pinsEditable) return false;
            p.pinToggled(app);
            return true;
        }
        // Show the launcher's apps as a list (true) or a grid; remembered across restarts.
        function setListView(list: bool): void { shell.setLauncherListView(list); }
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
                                    categories: (launcher.item?.panel.categories ?? []).map(c => c.id),
                                    used: Object.keys(launcher.item?.panel.usage ?? {}) });
        }
    }

    // Notification popups (plan 2.8), on the screen the keyboard is on; loaded while there are any, and until the
    // last has played its closing motion.
    property bool notificationPopupsShown: false
    Connections {
        target: NotificationService
        function onPopupsChanged() {
            if (NotificationService.popups.length > 0) shell.notificationPopupsShown = true;
        }
    }
    LazyLoader {
        id: notificationPopups
        active: shell.notificationPopupsShown
        NotificationPopupWindow {
            screen: Quickshell.screens.find(s => s.name === NiriService.focusedOutput) ?? Quickshell.screens[0]
            onFinished: shell.notificationPopupsShown = false
        }
    }
    LazyLoader {
        id: notificationList
        NotificationPanelWindow {
            screen: shell.notificationListScreen
            onCloseRequested: notificationList.active = false
        }
    }
    IpcHandler {
        target: "notifications"
        // the list, from a niri keybind: quickshell -p <path>/shell/shell.qml ipc call notifications toggle
        function toggle(): void { shell.toggleNotificationList(null); }
        function isOpen(): bool { return shell.notificationListOpen; }
        function dnd(): bool { return NotificationService.dnd; }
        function setDnd(on: bool): void { NotificationService.setDnd(on); }
        function dismiss(id: int): void { NotificationService.dismiss(id); }
        function dismissAll(): void { NotificationService.dismissAll(); }
        function invoke(id: int, action: string): void { NotificationService.invoke(id, action); }
        // What is kept and what pops up, as JSON: for diagnostics and the smoke test.
        function state(): string {
            return JSON.stringify({
                dnd: NotificationService.dnd,
                list: NotificationService.list.map(n => ({ id: n.id, app: n.appName, summary: n.summary, body: n.body })),
                popups: NotificationService.popups.map(n => n.id),
                windowLoaded: notificationPopups.active,
                listOpen: shell.notificationListOpen,
                listLoaded: notificationList.active,
                listShown: notificationList.item ? notificationList.item.panel.notifications.map(n => n.id) : [],
                bells: statusWindows.instances.map(s => s.pill.bell.iconName),
                bellsOpen: statusWindows.instances.map(s => s.pill.bell.open),
                shown: notificationPopups.item ? notificationPopups.item.popups.popups.map(n => n.id) : []
            });
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
                darkTheme: shellBackend.darkTheme,
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
