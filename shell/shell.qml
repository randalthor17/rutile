//@ pragma Env QT_QPA_PLATFORMTHEME = xdgdesktopportal
//@ pragma IconTheme Papirus-Dark
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION = 1
// (Above: file dialogs go through the desktop portal, the user's own file chooser; read at start, D51. Icons from
// Papirus-Dark, which has most apps' (tray icons sent by name; D62): the package brings it; an app's own icon in
// hicolor is still found.)
// Rutile Shell. Run with:   quickshell -p shell/shell.qml   (or `qs -p shell`)
// A clock sits at the top left of every screen, a status pill at the top right and the shelf along the bottom; clicking the pill opens Quick Settings on that screen, clicking the clock the calendar (D93).
// From a niri keybind:   quickshell -p <path>/shell/shell.qml ipc call quicksettings toggle
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Polkit
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs.common
import qs.bar
import qs.calendar
import qs.capture
import qs.clipboard
import qs.wallhaven
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
import qs.desktop
import qs.widgetsapp
import qs.widgethost
import "quicksettings/Controls.js" as Controls
import "quicksettings/Media.js" as Media
import "calendar/Calendar.js" as CalendarModel
import "lock/LockWallpaper.js" as LockWallpaper
import "power/PowerActions.js" as PowerActions
import "bar/TrayModel.js" as TrayModel
import "settingsapp/Model.js" as SettingsModel
import "desktop/Desktop.js" as Desktop
import "settingsapp/Pages.js" as SettingsPages
import "services/SettingsSchema.js" as SettingsSchema

ShellRoot {
    id: shell

    // The screen Quick Settings opens on; null lets the compositor choose (the focused output on niri).
    property var quickSettingsScreen: null

    // Open, and not on its way out: a closing panel plays its motion before the loader drops it.
    readonly property bool quickSettingsOpen: quickSettings.active && !(quickSettings.item?.closing ?? false)

    // A press on the shell's own desktop surfaces (wallpaper, widgets, shelf, clock) closes the popups that close on
    // focus loss: niri moves no keyboard focus on such a press, so they would stay open (D41's gap, D90).
    function closePopups() {
        if (quickSettingsOpen) closeQuickSettings();
        if (launcherOpen) closeLauncher();
        if (notificationListOpen) closeNotificationList();
        if (calendarOpen) closeCalendar();
        if (clipboardOpen) closeClipboard();
        if (captureOpen) closeCapture();
        if (wallhavenOpen) closeWallhaven();
    }

    // Screenshots and recording (D120): the capture bar on a screen (null: the first), as the launcher; what was
    // chosen is taken once the bar is off the screen. A toast says where it went, with Open.
    property var captureScreen: null
    readonly property bool captureOpen: capture.active && !(capture.item?.closing ?? false)
    function closeCapture() {
        if (capture.item) capture.item.close();
        else capture.active = false;
    }
    function toggleCapture(screen) {
        if (captureOpen) {
            closeCapture();
            return;
        }
        capture.active = false;
        captureScreen = screen;
        capture.active = true;
    }
    function captureOutput() {
        return (captureScreen ?? Quickshell.screens[0])?.name ?? "";
    }
    function takeCapture(c) {
        if (c.mode === "record") return CaptureService.record(c.target, captureOutput(), c.audio);
        return CaptureService.screenshot(c.target, captureOutput());
    }
    LazyLoader {
        id: capture
        CaptureWindow {
            screen: shell.captureScreen
            bar.windows: CaptureService.niri
            onCloseRequested: {
                const c = chosen;
                capture.active = false;
                if (c) {
                    captureLater.chosen = c;
                    captureLater.restart();
                }
            }
        }
    }
    // the compositor drops the bar's surface a frame or two after it is unloaded
    Timer {
        id: captureLater
        property var chosen: null
        interval: 250
        onTriggered: shell.takeCapture(chosen)
    }
    Connections {
        target: CaptureService
        function onDone(kind, path, ok) {
            if (!ok) {
                if (kind === "recording" && path !== "") ToastService.show("Recording stopped", { icon: "videocam_off" });
                return;
            }
            const what = kind === "recording" ? "Recording saved" : path !== "" ? "Screenshot saved and copied" : "Screenshot copied";
            ToastService.show(what, { icon: kind === "recording" ? "videocam" : "photo_camera",
                                      action: path !== "" ? { text: "Open", run: () => Qt.openUrlExternally("file://" + path) } : null });
        }
    }
    // From a key in niri: Print { spawn "rutile-shell" "capture" "open"; }
    IpcHandler {
        target: "capture"
        function open(): void { if (!shell.captureOpen) shell.toggleCapture(null); }
        function close(): void { shell.closeCapture(); }
        function toggle(): void { shell.toggleCapture(null); }
        // at once, without the bar: region, window (niri only) or screen; false when it cannot be taken
        function screenshot(target: string): bool { return CaptureService.screenshot(target, shell.captureOutput()); }
        function record(target: string, audio: bool): bool { return CaptureService.record(target, shell.captureOutput(), audio); }
        function stop(): bool { return CaptureService.stop(); }
        // as a click on the open bar's button: region, window or screen
        function choose(target: string): bool {
            const b = capture.item?.bar;
            if (!b || ["region", "window", "screen"].indexOf(target) < 0) return false;
            b.take(target);
            return true;
        }
        function setRecord(on: bool): bool {
            const b = capture.item?.bar;
            if (!b) return false;
            b.record = on;
            return true;
        }
        function state(): string {
            return JSON.stringify({ open: shell.captureOpen, niri: CaptureService.niri, recording: CaptureService.recording,
                                    recordingPath: CaptureService.recordingPath,
                                    pills: statusWindows.instances.map(s => s.pill.record.visible) });
        }
    }

    // Clipboard history (D119): ClipboardService keeps it from the start (its watchers); the picker, as the
    // launcher, opens on a screen (null: the compositor's choice) only while asked for.
    readonly property bool clipboardHistory: ClipboardService.enabled
    property var clipboardScreen: null
    readonly property bool clipboardOpen: clipboard.active && !(clipboard.item?.closing ?? false)
    function closeClipboard() {
        if (clipboard.item) clipboard.item.close();
        else clipboard.active = false;
    }
    function toggleClipboard(screen) {
        const here = screen === null || screen === clipboardScreen;
        if (clipboardOpen && here) {
            closeClipboard();
            return;
        }
        if (clipboard.item?.closing && here) {
            clipboard.item.reopen();
            return;
        }
        clipboard.active = false;
        clipboardScreen = screen;
        clipboard.active = true;
    }
    LazyLoader {
        id: clipboard
        ClipboardWindow {
            screen: shell.clipboardScreen
            onCloseRequested: clipboard.active = false
        }
    }
    // From a key in niri: Mod+V { spawn "rutile-shell" "clipboard" "toggle"; }
    IpcHandler {
        target: "clipboard"
        function toggle(): void { shell.toggleClipboard(null); }
        function open(): void { if (!shell.clipboardOpen) shell.toggleClipboard(null); }
        function close(): void { shell.closeClipboard(); }
        function isOpen(): bool { return shell.clipboardOpen; }
        // the open picker's entry at `index` (as shown), as a click: copied back, and the picker closes
        function choose(index: int): bool {
            const p = clipboard.item?.panel;
            const e = p?.results[index];
            if (!e) return false;
            p.chosen(e);
            return true;
        }
        function state(): string {
            return JSON.stringify({ history: ClipboardService.enabled, open: shell.clipboardOpen,
                                    entries: ClipboardService.entries.map(e => e.text) });
        }
    }

    // The Wallhaven browser (D128), as the clipboard picker: on a screen (null: the compositor's choice) only while
    // asked for; from the desktop's menu, Settings > Wallpaper & style, or a key.
    property var wallhavenScreen: null
    readonly property bool wallhavenOpen: wallhaven.active && !(wallhaven.item?.closing ?? false)
    function closeWallhaven() {
        if (wallhaven.item) wallhaven.item.close();
        else wallhaven.active = false;
    }
    function toggleWallhaven(screen) {
        const here = screen === null || screen === wallhavenScreen;
        if (wallhavenOpen && here) {
            closeWallhaven();
            return;
        }
        if (wallhaven.item?.closing && here) {
            wallhaven.item.reopen();
            return;
        }
        wallhaven.active = false;
        wallhavenScreen = screen;
        wallhaven.active = true;
    }
    LazyLoader {
        id: wallhaven
        WallhavenWindow {
            screen: shell.wallhavenScreen
            onCloseRequested: wallhaven.active = false
        }
    }
    // From a key in niri: Mod+Shift+W { spawn "rutile-shell" "wallhaven" "toggle"; }
    IpcHandler {
        target: "wallhaven"
        function toggle(): void { shell.toggleWallhaven(null); }
        function open(): void { if (!shell.wallhavenOpen) shell.toggleWallhaven(null); }
        function close(): void { shell.closeWallhaven(); }
        function isOpen(): bool { return shell.wallhavenOpen; }
        // a search as typed in the open browser (its filters kept), from the first page
        function search(query: string): bool {
            if (!wallhaven.item) return false;
            WallhavenService.setFilters({ query: query });
            return true;
        }
        // the open browser's result at `index`, as a click: downloaded and set as the wallpaper
        function choose(index: int): bool {
            const p = wallhaven.item?.panel;
            const w = p?.wallpapers[index];
            if (!w || p.applying !== "") return false;
            p.chosen(w);
            return true;
        }
        function state(): string {
            return JSON.stringify({ open: shell.wallhavenOpen, loading: WallhavenService.loading,
                                    error: WallhavenService.error, page: WallhavenService.page,
                                    pages: WallhavenService.pages, applying: WallhavenService.applying,
                                    results: WallhavenService.wallpapers.map(w => w.id) });
        }
    }

    // The calendar under the clock (D93), as the notification list: on a screen (null: the compositor's choice). A
    // press on the clock closes the other popups and opens or closes it.
    property var calendarScreen: null
    readonly property bool calendarOpen: calendar.active && !(calendar.item?.closing ?? false)
    function closeCalendar() {
        if (calendar.item) calendar.item.close();
        else calendar.active = false;
    }
    function toggleCalendar(screen) {
        const here = screen === null || screen === calendarScreen;
        if (calendarOpen && here) {
            closeCalendar();
            return;
        }
        if (calendar.item?.closing && here) {
            calendar.item.reopen();
            return;
        }
        calendar.active = false;
        calendarScreen = screen;
        calendar.active = true;
    }
    function clockPressed(screen) {
        if (quickSettingsOpen) closeQuickSettings();
        if (launcherOpen) closeLauncher();
        if (notificationListOpen) closeNotificationList();
        toggleCalendar(screen);
    }

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
            onEditWidgetsRequested: shell.widgetsEditing = true
            onWallpaperSettingsRequested: shell.openSettings("wallpaper", "")
            onWallhavenRequested: shell.toggleWallhaven(modelData)
            onPressed: shell.closePopups()
        }
    }

    // Widgets on the desktop (plan 4.4, D81): each screen's own, saved in state.json by output name. A screen's
    // layer exists only while it has widgets or they are being edited (D31); the files are read once for all.
    property bool widgetsEditing: false
    // while editing, every screen shows its empty workspace, the apps out of the way (niri has no minimize, D86)
    onWidgetsEditingChanged: widgetsEditing ? NiriService.showDesktop() : NiriService.hideDesktop()
    readonly property var desktopLayouts: Settings.stateValue("desktop.widgets", {})
    function saveDesktop(screenName, items) {
        Settings.setState("desktop.widgets", Desktop.withScreen(desktopLayouts, screenName, items));
    }
    // Places an absolute path on the screen niri has focused (the first one without niri); false when it is
    // relative or there is no room.
    function addWidget(path) {
        if (!path.startsWith("/")) return false;
        const name = NiriService.focusedOutput || (Quickshell.screens[0]?.name ?? "");
        const items = Desktop.placed(desktopLayouts, name);
        const d = desktops.instances.find(l => l.modelData.name === name);
        const grid = d?.item?.content.grid;
        const size = grid ? grid.fitNew(Desktop.NEW_SIZE) : Desktop.NEW_SIZE;
        if (!size) return false;
        saveDesktop(name, Desktop.withAdded(items, path, size));
        return true;
    }
    // The size widget `item` gets on screen `name` (its own, or smaller to fit), or null when that screen is full or
    // has no layer (only while editing or showing widgets).
    function desktopRoom(name, item) {
        const grid = desktops.instances.find(l => l.modelData.name === name)?.item?.content.grid;
        return grid ? grid.fitNew({ w: item.w, h: item.h }) : null;
    }
    // Moves widget `id` to screen `to`, into the first cells with room there; false when there is none, or no such
    // widget or screen.
    function moveWidget(id, to) {
        if (!Quickshell.screens.some(s => s.name === to)) return false;
        for (const name in desktopLayouts) {
            const items = Desktop.placed(desktopLayouts, name);
            const at = items.findIndex(i => i.id === id);
            if (at < 0) continue;
            if (name === to) return false;
            const size = desktopRoom(to, items[at]);
            if (!size) return false;
            Settings.setState("desktop.widgets", Desktop.withMoved(desktopLayouts, name, at, to, size));
            return true;
        }
        return false;
    }
    WidgetLibrary {
        id: widgetLibrary
        paths: Desktop.paths(shell.desktopLayouts)
    }
    Variants {
        id: desktops
        model: Quickshell.screens
        LazyLoader {
            id: desktop
            required property var modelData
            readonly property var items: Desktop.placed(shell.desktopLayouts, modelData.name)
            active: shell.widgetsEditing || items.length > 0
            DesktopWindow {
                id: desktopWindow
                screen: desktop.modelData
                items: desktop.items
                specs: widgetLibrary.specs
                available: widgetLibrary.available
                editMode: shell.widgetsEditing
                columns: Settings.value("widgets.columns") ?? 12
                scaleText: Settings.value("widgets.scaleText") === true
                commitHandler: next => shell.saveDesktop(desktop.modelData.name, next)
                screens: Quickshell.screens.filter(s => s.name !== desktop.modelData.name)
                    .map(s => ({ name: s.name, label: s.model ? s.model + " (" + s.name + ")" : s.name }))
                roomOn: (name, item) => shell.desktopRoom(name, item)
                onMoveRequested: (index, screen) => shell.moveWidget(desktop.items[index]?.id ?? "", screen)
                onDoneRequested: shell.widgetsEditing = false
                onPressed: shell.closePopups()
                onAddListRequested: widgetLibrary.scan()
                onEditRequested: index => {
                    shell.widgetsEditing = true;
                    desktopWindow.content.select(index);
                }
                onGalleryRequested: {
                    shell.widgetsEditing = false;
                    shell.openWidgets("");
                }
            }
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
    // The media keys (D117): the player Quick Settings' card shows by default (the one playing, else the first).
    // Bind them in niri: XF86AudioPlay { spawn "rutile-shell" "media" "playPause"; }
    IpcHandler {
        target: "media"
        function playPause(): bool {
            const p = Media.current(Mpris.players.values, "");
            if (!p || !p.canTogglePlaying) return false;
            p.togglePlaying();
            return true;
        }
        function next(): bool {
            const p = Media.current(Mpris.players.values, "");
            if (!p || !p.canGoNext) return false;
            p.next();
            return true;
        }
        function previous(): bool {
            const p = Media.current(Mpris.players.values, "");
            if (!p || !p.canGoPrevious) return false;
            p.previous();
            return true;
        }
        function state(): string {
            const p = Media.current(Mpris.players.values, "");
            return JSON.stringify({ players: Mpris.players.values.map(x => x.identity),
                                    current: p ? { identity: p.identity, title: p.trackTitle, artist: p.trackArtist,
                                                   playing: p.isPlaying } : null });
        }
    }

    // Keep awake (D116): an idle inhibitor on a 1 px surface of its own on the overlay layer, which stays above a
    // fullscreen window (an inhibitor holds only while its surface shows), created only while on (D31).
    LazyLoader {
        id: keepAwake
        active: KeepAwakeService.on
        PanelWindow {
            id: keepAwakeSurface
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "rutile-keep-awake"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            IdleInhibitor {
                window: keepAwakeSurface
                enabled: true
            }
        }
    }
    // How see-through the panels are (D115).
    Binding {
        target: Panels
        property: "opacity"
        value: Math.max(0.5, Math.min(1, Settings.value("style.panelOpacity") ?? 1))
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
    // pages ("" keeps the one showing), `key` rings one of its settings. There is one window: opened again (Quick
    // Settings, the launcher, its desktop file, IPC) it is reused, and niri focuses it, as Quickshell cannot raise
    // a window it already shows (a new one niri focuses itself).
    readonly property bool settingsOpen: settingsApp.active
    function openSettings(page, key) {
        const reused = settingsApp.active;
        settingsApp.active = true;
        const app = settingsApp.item?.app;
        if (!app) return false;
        if (reused) NiriService.focusOwnWindow(settingsApp.item.title);
        return page === "" || app.openPage(page, key ?? "");
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
        // A page with one of its settings ringed, as the launcher's settings results open it
        function openSetting(page: string, key: string): bool { return shell.openSettings(page, key); }
        function close(): void { settingsApp.active = false; }
        function toggle(): void {
            if (settingsApp.active) settingsApp.active = false;
            else shell.openSettings("");
        }
        function isOpen(): bool { return settingsApp.active; }
        function state(): string {
            const app = settingsApp.item?.app;
            return JSON.stringify({ open: settingsApp.active, page: app?.currentPage ?? "", query: app?.query ?? "",
                                    highlight: app?.highlightKey ?? "",
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

    // A widget file shown with its live data (D80), until the desktop grid shows widgets: one window, created only
    // while open. From a terminal: rutile-shell widgets preview ~/my-widget.json
    property string widgetPreviewPath: ""
    LazyLoader {
        id: widgetPreview
        WidgetPreviewWindow {
            path: shell.widgetPreviewPath
            onFinished: Qt.callLater(() => widgetPreview.active = false)
        }
    }
    // The Widgets app (plan 4.5, D82): the templates and the user's widgets; one window, created only while open.
    function openWidgets(category) {
        const reused = widgetsApp.active;
        widgetsApp.active = true;
        const w = widgetsApp.item;
        if (!w) return false;
        if (reused) NiriService.focusOwnWindow(w.title);
        return category === "" || w.app.openCategory(category);
    }
    LazyLoader {
        id: widgetsApp
        WidgetsWindow {
            onFinished: Qt.callLater(() => widgetsApp.active = false)
            onPlaceRequested: path => shell.addWidget(path)
            onPreviewRequested: path => {
                shell.widgetPreviewPath = path;
                widgetPreview.active = true;
            }
        }
    }
    WidgetChecker { id: widgetChecker }
    IpcHandler {
        target: "widgets"
        // A widget file checked as tools/widget_check.py would (D85): "PATH: $.where: what" lines, then ok or FAILED
        function check(path: string): string { return widgetChecker.report(path); }
        // The same as JSON: {"ok", "problems": [{"path", "message"}]}
        function checkJson(path: string): string { return JSON.stringify(widgetChecker.check(path)); }
        // An absolute path; false for a relative one. Another file replaces the one shown.
        function preview(path: string): bool {
            if (!path.startsWith("/")) return false;
            shell.widgetPreviewPath = path;
            widgetPreview.active = true;
            return true;
        }
        function close(): void { widgetPreview.active = false; }
        // The desktop grid (D81): edit mode on every screen, and back.
        function edit(): void { shell.widgetsEditing = true; }
        function done(): void { shell.widgetsEditing = false; }
        // An absolute path, on the focused screen; false for a relative one or no room.
        function add(path: string): bool { return shell.addWidget(path); }
        // Widget `id` to the screen named `screen` (its output name), while editing; false when it has no room there.
        function move(id: string, screen: string): bool { return shell.moveWidget(id, screen); }
        function remove(id: string): bool {
            for (const name in shell.desktopLayouts) {
                const items = Desktop.placed(shell.desktopLayouts, name);
                const at = items.findIndex(i => i.id === id);
                if (at >= 0) {
                    shell.saveDesktop(name, Desktop.withoutIndex(items, at));
                    return true;
                }
            }
            return false;
        }
        // The Widgets app (D82): one window, brought forward when open; "" for the category it shows.
        function gallery(category: string): bool { return shell.openWidgets(category); }
        function galleryClose(): void { widgetsApp.active = false; }
        // Uses a template by name (weather-1), as its Use button does.
        function use(template: string): bool {
            const w = widgetsApp.item;
            const t = w?.app.templates.find(e => e.path.endsWith("/" + template + ".json"));
            return !!t && w.use(t.path);
        }
        function galleryState(): string {
            const w = widgetsApp.item;
            return JSON.stringify({ open: widgetsApp.active, category: w?.app.currentCategory ?? "",
                                    shown: (w?.app.shown ?? []).map(e => e.path.replace(/^.*\//, "")),
                                    drawn: (w?.app.shown ?? []).filter(e => w.app.specs[e.path]).length,
                                    lastCreated: w?.lastCreated ?? "" });
        }
        function layout(): string {
            return JSON.stringify({ editing: shell.widgetsEditing, screens: shell.desktopLayouts,
                                    shown: desktops.instances.filter(l => l.item).map(l => l.modelData.name),
                                    readable: Object.keys(widgetLibrary.specs).filter(p => widgetLibrary.specs[p] !== null).sort() });
        }
        function state(): string {
            const w = widgetPreview.item;
            return JSON.stringify({ open: widgetPreview.active, path: w?.path ?? "", name: w?.spec?.name ?? "",
                                    problems: w?.problems ?? [], sourceErrors: w?.sourceErrors ?? [],
                                    sources: w ? Object.keys(w.values).sort() : [] });
        }
    }

    // Other apps in the shell's colors (D52; all off by default): created at start so it follows the palette.
    readonly property var appColorsWanted: AppColorsService.wanted
    // The shell's settings into niri (D70, D74): created with the shell, so the files follow the settings, and
    // Display's choices are put first again when niri's config changes
    readonly property string niriSettingsError: NiriSettingsService.error
    readonly property string niriDisplayError: NiriDisplayService.error
    IpcHandler {
        target: "appcolors"
        function state(): string {
            return JSON.stringify({ enabled: AppColorsService.enabled, wanted: AppColorsService.wanted,
                                    synced: AppColorsService.synced, runs: AppColorsService.runs,
                                    error: AppColorsService.lastError });
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
        source: LockWallpaper.url(WallpaperService.path)
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
            calendarOpen: shell.calendarOpen && calendar.item?.screen === modelData
            onClockPressed: shell.clockPressed(modelData)
            trayItems: shell.trayItems
            trayMenuId: shell.trayMenuOpen && trayMenu.item?.screen === modelData ? shell.trayMenuId : ""
            onTrayMenuRequested: (entry, right) => shell.toggleTrayMenu(modelData, entry, right)
            inputOpen: shell.trayMenuOpen && trayMenu.item?.screen === modelData && shell.trayMenuId === TrayModel.INPUT_METHOD
            onInputClicked: right => shell.inputClicked(modelData, right)
        }
    }

    // App indicators (plan 2.10, D61): the tray's items, shown in every status bar; one app's menu at a time,
    // loaded only while open (D31). It closes when its app leaves the tray.
    readonly property var trayItems: TrayModel.shown(SystemTray.items.values, Status.Passive, Status.NeedsAttention)
    property string trayMenuId: ""
    property var trayMenuEntry: null
    property var trayMenuScreen: null
    property real trayMenuRight: 0
    readonly property bool trayMenuOpen: trayMenu.active && !(trayMenu.item?.closing ?? false)
    function toggleTrayMenu(screen, entry, right) {
        const same = trayMenuOpen && trayMenuId === entry.id && trayMenuScreen === screen;
        closeTrayMenu();
        if (same) return;
        trayMenu.active = false;
        trayMenuId = entry.id;
        trayMenuEntry = entry;
        trayMenuScreen = screen;
        trayMenuRight = right;
        trayMenu.active = true;
    }
    function closeTrayMenu() {
        if (trayMenu.item) trayMenu.item.close();
    }
    onTrayItemsChanged: if (trayMenu.active && !trayItems.concat(inputEntry ? [inputEntry] : []).some(e => e.id === trayMenuId))
        trayMenu.active = false

    // Typing in other languages (D118): fcitx5's own menu from the input pill, or the next input method without it.
    // Its tray icon changes with every switch (also by its hotkey): the service reads again then.
    readonly property var inputEntry: TrayModel.inputMethod(SystemTray.items.values)
    function inputClicked(screen, right) {
        if (inputEntry) toggleTrayMenu(screen, inputEntry, right);
        else InputMethodService.next();
    }
    IpcHandler {
        target: "input"
        // the next input method of fcitx5's current group (bind it to a key); false while fcitx5 is not there
        function next(): bool { return InputMethodService.next(); }
        // an input method by its fcitx5 name (keyboard-us, m17n_bn_itrans), from the current group
        function set(name: string): bool { return InputMethodService.set(name); }
        function configure(): void { InputMethodService.configure(); }
        function state(): string {
            return JSON.stringify({ available: InputMethodService.available, current: InputMethodService.shown?.id ?? "",
                                    methods: InputMethodService.methods.map(m => m.id),
                                    labels: statusWindows.instances.map(s => s.pill.input.visible ? s.pill.input.label : ""),
                                    started: InputMethodService.started, inTray: shell.trayItems.some(e => e.id === TrayModel.INPUT_METHOD) });
        }
    }
    Connections {
        target: shell.inputEntry?.item ?? null
        ignoreUnknownSignals: true
        function onIconChanged() { InputMethodService.refresh(); }
        function onTooltipTitleChanged() { InputMethodService.refresh(); }
    }
    LazyLoader {
        id: trayMenu
        TrayMenuWindow {
            screen: shell.trayMenuScreen
            trayItem: shell.trayMenuEntry.item
            right: shell.trayMenuRight
            onCloseRequested: trayMenu.active = false
        }
    }
    // Scripts and the smoke test: what the tray shows, and its items' clicks and menus.
    IpcHandler {
        target: "tray"
        function state(): string {
            const w = trayMenu.item;
            return JSON.stringify({ items: shell.trayItems.map(e => ({ id: e.id, title: e.title, attention: e.attention, icon: e.icon })),
                                    menuOpen: shell.trayMenuOpen, loaded: trayMenu.active, menuFor: shell.trayMenuId,
                                    entries: w ? w.panel.entries.map(e => e.separator ? "-" : e.text) : [],
                                    depth: w ? w.levels.length - 1 : 0 });
        }
        // as a left click on its icon
        function activate(id: string): bool {
            const e = shell.trayItems.find(t => t.id === id);
            if (!e) return false;
            e.item.activate();
            return true;
        }
        // as a right click on its icon, in the first status bar
        function openMenu(id: string): bool {
            const e = shell.trayItems.find(t => t.id === id);
            const w = statusWindows.instances[0]?.pill;
            if (!e || !e.item.hasMenu || !w) return false;
            shell.toggleTrayMenu(w.screen, e, w.margins.right + w.width - (w.tray.x + w.tray.rightOf(id)));
            return true;
        }
        function closeMenu(): void { shell.closeTrayMenu(); }
        // the open menu's entry with this text, as a click (a submenu opens in place)
        function choose(text: string): bool {
            const w = trayMenu.item;
            if (!w) return false;
            const i = w.children.findIndex(c => TrayModel.label(c.text) === text);
            return i >= 0 && w.choose(i);
        }
        function back(): void { trayMenu.item?.pop(); }
        // Where the shell finds an icon by name ("": nowhere): to see why a tray icon is missing.
        function iconPath(name: string): string { return Quickshell.iconPath(name, true); }
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
            onPressed: shell.closePopups()
            onMenuRequested: (target, x) => shell.openShelfMenu(modelData, target, x, shelf.height)
        }
    }

    // A shelf button's right-click menu (D72), loaded only while open (D31).
    property var shelfMenuScreen: null
    property var shelfMenuTarget: null
    property real shelfMenuX: 0
    property real shelfMenuShelfHeight: 0
    readonly property bool shelfMenuOpen: shelfMenu.active && !(shelfMenu.item?.closing ?? false)
    function openShelfMenu(screen, target, x, shelfHeight) {
        shelfMenu.active = false;
        shelfMenuScreen = screen;
        shelfMenuTarget = target;
        shelfMenuX = x;
        shelfMenuShelfHeight = shelfHeight;
        shelfMenu.active = true;
    }
    // Scripts and tests: the shelf's pins, and its right-click menu (as a right click on a pin or a window).
    IpcHandler {
        target: "shelf"
        function state(): string {
            const shelf = shelves.instances[0];
            return JSON.stringify({ pins: shelfBackend.pinnedIds, menuOpen: shell.shelfMenuOpen,
                                    menu: shelfMenu.item ? shelfMenu.item.items.map(i => i.separator ? "-" : i.text) : [],
                                    tooltip: shelf?.shelf.tooltipText ?? "", tooltipLoaded: shelf?.tooltip.active ?? false,
                                    tooltipShown: (shelf?.tooltip.item?.tooltip.opacity ?? 0) === 1 });
        }
        // the first screen's shelf shows TEXT as a hovered button's tooltip, mid-shelf; "" hides it (D106)
        function tooltip(text: string): void {
            const shelf = shelves.instances[0]?.shelf;
            if (!shelf) return;
            shelf.tooltipX = shelf.width / 2;
            shelf.tooltipText = text;
        }
        // TARGET: a pinned app's id, or window:<niri window id>; on the first screen's shelf
        function openMenu(target: string): bool {
            const shelf = shelves.instances[0];
            if (!shelf) return false;
            let t = null;
            if (target.startsWith("window:")) {
                const id = Number(target.slice(7));
                for (const g of shelf.shelf.groups)
                    for (const w of g.windows) if (w.id === id) t = { window: w };
            } else {
                const app = shelfBackend.pinned.find(p => p.id === target);
                if (app) t = { app: app };
            }
            if (!t) return false;
            shell.openShelfMenu(shelf.screen, t, shelf.width / 2, shelf.shelf.height);
            return true;
        }
        // an entry of the open menu by its text, as a click
        function choose(text: string): bool {
            const w = shelfMenu.item;
            const it = w ? w.items.find(i => i.text === text) : null;
            if (!it) return false;
            w.chosen(it.id);
            w.close();
            return true;
        }
        function closeMenu(): void {
            if (shelfMenu.item) shelfMenu.item.close();
        }
    }
    LazyLoader {
        id: shelfMenu
        ShelfMenuWindow {
            screen: shell.shelfMenuScreen
            items: shelfBackend.menuFor(shell.shelfMenuTarget)
            centerX: shell.shelfMenuX
            shelfHeight: shell.shelfMenuShelfHeight
            onChosen: id => shelfBackend.runMenu(shell.shelfMenuTarget, id)
            onCloseRequested: shelfMenu.active = false
        }
    }

    LazyLoader {
        id: launcher
        LauncherWindow {
            screen: shell.launcherScreen
            left: (shelves.instances.find(s => s.screen === screen) ?? shelves.instances[0])?.shelf.launcherX ?? Spacing.md
            listView: shell.launcherListView
            onListViewChanged: shell.setLauncherListView(listView)
            pinnedIds: shelfBackend.pinnedIds
            pinsEditable: shelfBackend.pinsEditable
            onPinToggled: app => shelfBackend.togglePin(app.id)
            // Quick Settings' controls as search results: a toggle flips, a slider opens Quick Settings; and the
            // Settings app's pages and settings, which open it there
            settings: Controls.searchItems(shellBackend)
            findSettings: query => SettingsModel.launcherItems(query, SettingsPages.pages, SettingsSchema.schema,
                                                               SettingsPages.hints, 5)
            onSettingChosen: item => {
                if (item.page !== undefined) shell.openSettings(item.page, item.key);
                else if (Controls.choose(item, shellBackend) === "open" && !shell.quickSettingsOpen)
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
            const item = p?.apps.concat(p.settings, p.results).find(a => a.id === id);
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
    // evolution-data-server starts on first use, and with online accounts that takes a second or more (D95). Started
    // a few seconds after the shell (a read of no time at all, which opens the calendars), it is running when the
    // calendar under the clock opens. It stays running, as in GNOME; the helper exits.
    Timer {
        interval: 3000
        running: true
        onTriggered: calendarWarmUp.running = true
    }
    Process {
        id: calendarWarmUp
        command: CalendarModel.edsCommand(CalendarModel.helperPath(Quickshell.env("RUTILE_CALENDAR"), Quickshell.shellDir),
                                          new Date(), new Date())
    }
    LazyLoader {
        id: calendar
        CalendarWindow {
            screen: shell.calendarScreen
            onCloseRequested: calendar.active = false
            onSettingsRequested: {
                shell.openSettings("calendar");
                shell.closeCalendar();
            }
        }
    }
    IpcHandler {
        target: "calendar"
        // from a niri keybind: quickshell -p <path>/shell/shell.qml ipc call calendar toggle
        function toggle(): void { shell.toggleCalendar(null); }
        function open(): void { if (!shell.calendarOpen) shell.toggleCalendar(null); }
        function close(): void { shell.closeCalendar(); }
        function isOpen(): bool { return shell.calendarOpen; }
        // Opens the calendar on a day, "2026-11-04"; false for anything else.
        function select(day: string): bool {
            const d = CalendarModel.parseDay(day);
            if (!d) return false;
            if (!shell.calendarOpen) shell.toggleCalendar(null);
            calendar.item.panel.select(d);
            return true;
        }
        // What it shows, as JSON: for diagnostics and the smoke test.
        function state(): string {
            const p = calendar.item?.panel;
            return JSON.stringify({
                open: shell.calendarOpen,
                loaded: calendar.active,
                read: calendar.item?.read ?? false,
                hasFolder: p?.hasFolder ?? false,
                feeds: calendar.item?.feeds.addresses.length ?? 0,
                feedsFailed: calendar.item?.feeds.failed.length ?? 0,
                feedsBusy: calendar.item?.feeds.busy ?? false,
                eds: calendar.item?.eds.available ?? false,
                edsSynced: calendar.item?.eds.synced ?? false,
                app: calendar.item?.hasApp ?? false,
                month: p ? CalendarModel.dayKey(p.month).substring(0, 7) : "",
                selected: p ? CalendarModel.dayKey(p.selected) : "",
                events: p ? p.dayEvents : [],
                clocksOpen: statusWindows.instances.map(s => s.clock.open)
            });
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
        // the microphone's mute (XF86AudioMicMute), shown in the OSD; false without a microphone
        function toggleMicMute(): bool {
            if (!AudioService.micAvailable) return false;
            AudioService.setMicMuted(!AudioService.micMuted);
            shell.showOsd("mic");
            return true;
        }
        // false without a backlight
        function brightnessUp(): bool { return shell.stepBrightness(shell.osdStep); }
        function brightnessDown(): bool { return shell.stepBrightness(-shell.osdStep); }
        // not `show`: the CLI takes `ipc call <target> show` for its own `ipc show` command
        function display(kind: string): void { shell.showOsd(["brightness", "mic"].indexOf(kind) >= 0 ? kind : "volume"); }
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
            // the tile layout, kept in state.json (plan 2.6); a saved one with unknown tiles shows the rest
            tiles: Controls.tiles(Settings.stateValue("quicksettings.tiles", null))
            onTilesEdited: tiles => Settings.setState("quicksettings.tiles", tiles)
            onCloseRequested: quickSettings.active = false
            onPowerMenuRequested: {
                shell.openPowerMenu(screen);
                shell.closeQuickSettings();
            }
            onSettingsRequested: {
                shell.openSettings("");
                shell.closeQuickSettings();
            }
            onSoundSettingsRequested: {
                shell.openSettings("sound");
                shell.closeQuickSettings();
            }
            onSettingsPageRequested: page => {
                shell.openSettings(page);
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
        // Opens Quick Settings at a tile's detail page ("wifi", "bluetooth"); "" goes back to the tiles.
        function details(page: string): bool {
            if (["", "wifi", "bluetooth", "nightLight", "powerSaver", "mic"].indexOf(page) < 0) return false;
            if (!shell.quickSettingsOpen) shell.toggleQuickSettings(null);
            quickSettings.item.details = page;
            return true;
        }
        // Keep awake (the tile): on or off, for this session.
        function keepAwake(on: bool): void { KeepAwakeService.setOn(on); }
        // What the windows see, as JSON: for diagnostics and tools/qtws.py test-wayland.
        function state(): string {
            const w = quickSettings.item;
            return JSON.stringify({
                open: shell.quickSettingsOpen,
                loaded: quickSettings.active,
                panelHasBackend: !!w && w.panelHasBackend,
                brightnessShown: !!w && w.brightnessShown,
                details: w?.details ?? "",
                detailRows: w?.detailRows ?? [],
                darkTheme: shellBackend.darkTheme,
                keepAwake: keepAwake.active && !!keepAwake.item,
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
