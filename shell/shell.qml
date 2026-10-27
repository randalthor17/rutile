// Rutile Shell. Run with:   quickshell -p shell/shell.qml   (or `qs -p shell`)
// A clock sits at the top left of every screen, a status pill at the top right and the shelf along the bottom; clicking it opens Quick Settings on that screen.
// From a niri keybind:   quickshell -p <path>/shell/shell.qml ipc call quicksettings toggle
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.common
import qs.bar
import qs.launcher
import qs.notifications
import qs.osd
import qs.toast
import qs.lock
import qs.wallpaper
import qs.power
import qs.polkit
import qs.settingsapp
import qs.quicksettings
import qs.services
import qs.shelf
import "quicksettings/Controls.js" as Controls
import "lock/LockWallpaper.js" as LockWallpaper
import "power/PowerActions.js" as PowerActions

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

    // The wallpaper on every screen (plan 2.9), under everything.
    Variants {
        id: wallpapers
        model: Quickshell.screens
        WallpaperWindow {
            required property var modelData
            screen: modelData
        }
    }
    // From a script or keybind: quickshell -p <path>/shell/shell.qml ipc call wallpaper set /path/to/image.png
    IpcHandler {
        target: "wallpaper"
        // false when the path is not absolute or the setting is set in Nix; "" removes the wallpaper
        function set(path: string): bool { return WallpaperService.set(path); }
        function get(): string { return WallpaperService.path; }
        function state(): string {
            return JSON.stringify({ path: WallpaperService.path, error: WallpaperService.lastError,
                                    paletteFrom: Settings.stateValue("wallpaper.paletteFrom", ""),
                                    shown: wallpapers.instances.map(w => w.view.front.source.toString()),
                                    ready: wallpapers.instances.map(w => w.view.front.status === Image.Ready) });
        }
    }

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

    // The full-screen power menu (plan 2.8), on a screen (null: the compositor's choice), loaded only while open.
    // The action runs once the menu has played its closing motion and gone (PowerWindow.finished).
    property var powerScreen: null
    readonly property bool powerMenuOpen: powerMenu.active && !(powerMenu.item?.closing ?? false)
    function openPowerMenu(screen) {
        if (powerMenu.item?.closing) {
            powerMenu.item.reopen();
            return;
        }
        if (powerMenu.active) return;
        powerScreen = screen;
        powerMenu.active = true;
    }
    function closePowerMenu() {
        if (powerMenu.item) powerMenu.item.close();
    }
    function runPower(id) {
        if (id === "lock") {
            shell.lock("menu");
            return;
        }
        const command = PowerActions.command(id);
        if (command) Quickshell.execDetached(command);
    }
    LazyLoader {
        id: powerMenu
        PowerWindow {
            screen: shell.powerScreen
            onFinished: id => {
                powerMenu.active = false;
                shell.runPower(id);
            }
        }
    }
    // From a keybind: quickshell -p <path>/shell/shell.qml ipc call power toggle
    IpcHandler {
        target: "power"
        function toggle(): void {
            if (shell.powerMenuOpen) shell.closePowerMenu();
            else shell.openPowerMenu(null);
        }
        function open(): void { shell.openPowerMenu(null); }
        function close(): void { shell.closePowerMenu(); }
        function isOpen(): bool { return shell.powerMenuOpen; }
        // As a click on its button would (the smoke test): false when the menu is not open or the id is unknown.
        function choose(id: string): bool {
            const o = powerMenu.item?.overlay;
            const i = o ? o.actions.findIndex(a => a.id === id) : -1;
            if (i < 0) return false;            // no menu, or not one of its entries
            o.choose(i);
            return true;
        }
        function state(): string {
            return JSON.stringify({ open: shell.powerMenuOpen, loaded: powerMenu.active,
                                    actions: powerMenu.item ? powerMenu.item.overlay.actions.map(a => a.id) : [] });
        }
    }

    // The settings app (plan 5.1), a window of its own, created only while open (D31). `page` opens one of its
    // pages ("" keeps the one showing). Quickshell cannot raise a window that is already open; niri focuses a new one.
    readonly property bool settingsOpen: settingsApp.active
    function openSettings(page) {
        settingsApp.active = true;
        const app = settingsApp.item?.app;
        if (!app) return false;
        return page === "" || app.openPage(page);
    }
    LazyLoader {
        id: settingsApp
        SettingsWindow {
            onFinished: Qt.callLater(() => settingsApp.active = false)
        }
    }
    // From a keybind: quickshell -p <path>/shell/shell.qml ipc call settings open wallpaper
    IpcHandler {
        target: "settings"
        function open(page: string): bool { return shell.openSettings(page); }
        function close(): void { settingsApp.active = false; }
        function toggle(): void {
            if (settingsApp.active) settingsApp.active = false;
            else shell.openSettings("");
        }
        function isOpen(): bool { return settingsApp.active; }
        function state(): string {
            const app = settingsApp.item?.app;
            return JSON.stringify({ open: settingsApp.active, page: app?.currentPage ?? "", query: app?.query ?? "",
                                    results: app ? app.results.map(r => r.page + (r.key ? "/" + r.key : "")) : [] });
        }
        // As typing in its search field would (the smoke test).
        function search(text: string): bool {
            const app = settingsApp.item?.app;
            if (!app) return false;
            app.search.text = text;
            return true;
        }
    }

    // The polkit agent (plan 2.8): an app asking for an administrator's permission gets the shell's password dialog
    // on the focused screen, loaded only while polkit asks (D31). polkit allows one agent per session, so with
    // another one running (polkit.agent off, or it registered first) this one stays out of the way.
    readonly property var polkitFlow: polkitAgent.item?.flow ?? null
    onPolkitFlowChanged: if (polkitFlow) polkitDialog.active = true
    LazyLoader {
        id: polkitAgent
        active: Settings.value("polkit.agent") === true
        PolkitAgent {
            path: "/org/rutile/PolkitAgent"
            onIsRegisteredChanged: console.info("rutile: polkit agent " + (isRegistered ? "registered" : "not registered"))
        }
    }
    LazyLoader {
        id: polkitDialog
        PolkitWindow {
            flow: shell.polkitFlow
            onFinished: polkitDialog.active = false
        }
    }
    // Diagnostics and tests: never the password; cancel is what the dialog's Cancel does.
    IpcHandler {
        target: "polkit"
        function cancel(): bool {
            const d = polkitDialog.item?.dialog;
            if (!d?.shown) return false;
            d.cancel();
            return true;
        }
        function state(): string {
            const a = polkitAgent.item;
            const d = polkitDialog.item?.dialog;
            return JSON.stringify({ enabled: polkitAgent.active, registered: a?.isRegistered ?? false,
                                    active: a?.isActive ?? false, open: d?.shown ?? false, loaded: polkitDialog.active,
                                    actionId: d?.actionId ?? "", asking: d?.asking ?? false, wrong: d?.wrong ?? false });
        }
    }

    // The lock screen (plan 2.8), loaded only while locked (D31). Only a correct password unlocks it.
    // `reason`: menu, ipc, logind, sleep or idle. The first one of a lock is its reason; every request is kept
    // (the last 10) for the state, so a test can see one that came while it was already locked.
    property string lockReason: ""
    property var lockRequests: []
    function lock(reason) {
        lockRequests = lockRequests.concat([reason]).slice(-10);
        if (!lockScreen.active) lockReason = reason;
        lockScreen.active = true;
    }
    LazyLoader {
        id: lockScreen
        LockScreen {
            onUnlocked: Qt.callLater(() => lockScreen.active = false)
        }
    }
    // The lock screen's wallpaper, kept decoded (small, about 0.5 MB) so locking shows it at once (LockWallpaper.js).
    Image {
        visible: false
        source: LockWallpaper.url(Settings.value("wallpaper.path") ?? "")
        sourceSize: LockWallpaper.size
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    // logind's Lock (loginctl lock-session), suspend and idle (LockTriggers.qml).
    LockTriggers {
        locked: lockScreen.active
        secure: lockScreen.item?.secure ?? false
        onLockRequested: reason => shell.lock(reason)
    }
    // From a niri keybind: quickshell -p <path>/shell/shell.qml ipc call lock lock. There is deliberately no unlock.
    IpcHandler {
        target: "lock"
        function lock(): void { shell.lock("ipc"); }
        function isLocked(): bool { return lockScreen.active; }
        // diagnostics and tests: never the password
        function state(): string {
            const l = lockScreen.item;
            return JSON.stringify({ locked: lockScreen.active, secure: l?.secure ?? false, busy: l?.busy ?? false,
                                    error: l?.error ?? "", attempts: l?.attempts ?? 0,
                                    reason: lockScreen.active ? shell.lockReason : "", requests: shell.lockRequests });
        }
    }

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
        function reply(id: int, text: string): void { NotificationService.reply(id, text); }
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

    // The volume and brightness OSD (plan 2.8), on the screen the keyboard is on; loaded from a change until it has
    // played its closing motion. A change while it shows, or closes, keeps it open on the new kind.
    property bool osdShown: false
    property string osdKind: "volume"
    readonly property real osdStep: 0.05
    function showOsd(kind) {
        osdKind = kind;
        if (osd.item) osd.item.panel.show(kind);
        else osdShown = true;
    }
    LazyLoader {
        id: osd
        active: shell.osdShown
        OsdWindow {
            screen: Quickshell.screens.find(s => s.name === NiriService.focusedOutput) ?? Quickshell.screens[0]
            Component.onCompleted: panel.show(shell.osdKind)
            onFinished: shell.osdShown = false
        }
    }

    // A volume change from anywhere (keys bound to wpctl, an app, the OSD's own slider) shows the OSD, except while
    // Quick Settings is open: its slider shows the level already. The default output's first values, in the half
    // second after it appears or changes, are not changes.
    property bool volumeArmed: false
    function armVolume() {
        volumeArmed = false;
        volumeArm.restart();
    }
    Timer {
        id: volumeArm
        interval: 500
        onTriggered: shell.volumeArmed = AudioService.ready
    }
    function volumeChanged() {
        if (volumeArmed && !quickSettingsOpen) showOsd("volume");
    }
    Connections {
        target: AudioService
        function onReadyChanged() { shell.armVolume(); }
        function onSinkChanged() { shell.armVolume(); }
        function onVolumeChanged() { shell.volumeChanged(); }
        function onMutedChanged() { shell.volumeChanged(); }
    }
    Component.onCompleted: armVolume()

    // From niri's media keys, e.g. XF86AudioRaiseVolume allow-when-locked=true { spawn "qs" "-p" "<path>/shell/shell.qml"
    // "ipc" "call" "osd" "volumeUp"; } (brightnessctl reports no changes, so brightness keys must come here to show it).
    IpcHandler {
        target: "osd"
        function volumeUp(): void { AudioService.setVolume(AudioService.volume + shell.osdStep); }
        function volumeDown(): void { AudioService.setVolume(AudioService.volume - shell.osdStep); }
        function toggleMute(): void { AudioService.setMuted(!AudioService.muted); }
        // false without a backlight
        function brightnessUp(): bool { return shell.stepBrightness(shell.osdStep); }
        function brightnessDown(): bool { return shell.stepBrightness(-shell.osdStep); }
        // not `show`: the CLI takes `ipc call <target> show` for its own `ipc show` command
        function display(kind: string): void { shell.showOsd(kind === "brightness" ? "brightness" : "volume"); }
        function state(): string {
            const p = osd.item?.panel;
            return JSON.stringify({ loaded: osd.active, open: p?.open ?? false, kind: p?.kind ?? "",
                                    value: p?.value ?? 0, muted: p?.muted ?? false,
                                    volumeReady: AudioService.ready, brightness: BrightnessService.available });
        }
    }
    function stepBrightness(step) {
        if (!BrightnessService.available) return false;
        BrightnessService.set(BrightnessService.value + step);
        showOsd("brightness");
        return true;
    }

    // Toasts (plan 2.8), on the screen the keyboard is on; loaded while there is one.
    LazyLoader {
        id: toasts
        active: ToastService.current !== null
        ToastWindow {
            screen: Quickshell.screens.find(s => s.name === NiriService.focusedOutput) ?? Quickshell.screens[0]
        }
    }
    // From scripts and keybinds: quickshell -p <path>/shell/shell.qml ipc call toast send "Screenshot saved" photo_camera
    IpcHandler {
        target: "toast"
        // `icon`: a Material Symbols name, or "" for none; returns the toast's id
        // not `show`, which the CLI takes for its own `ipc show` command
        function send(text: string, icon: string): int { return ToastService.show(text, { icon: icon }); }
        function state(): string {
            const w = toasts.item;
            return JSON.stringify({ loaded: toasts.active, open: w?.toast.open ?? false,
                                    current: ToastService.current?.text ?? null,
                                    queued: ToastService.queue.map(q => q.text) });
        }
    }

    LazyLoader {
        id: quickSettings
        QuickSettingsWindow {
            screen: shell.quickSettingsScreen
            backend: shellBackend
            onCloseRequested: quickSettings.active = false
            onPowerMenuRequested: {
                shell.openPowerMenu(screen);
                shell.closeQuickSettings();
            }
            onSettingsRequested: {
                shell.openSettings("");
                shell.closeQuickSettings();
            }
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
