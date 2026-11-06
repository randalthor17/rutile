// The launcher's layer-shell surface: above the shelf's left end, its left edge on the launcher button's (D124; it
// keeps clear of the shelf's and the status strip's exclusive zones), keyboard focus on open. The shell creates it in a LazyLoader only while open (D31);
// close() plays the closing motion, then closeRequested asks the shell to unload it. The apps are the desktop
// entries Quickshell finds (DesktopEntries.applications: not hidden, not NoDisplay). Each app opened from here
// counts toward its usage (state.json's `launcher.usage`, Usage.js); Pin and Unpin go to the shell (`pinToggled`).
// An answer or an emoji chosen is copied with wl-copy, with a toast (D130). The emoji names are read from Unicode's
// emoji-test.txt (RUTILE_EMOJI_DATA; the package names unicode-emoji's) only once a search asks for emoji, and go
// with the launcher.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.services
import "Usage.js" as Usage
import "Answers.js" as Answers

PanelWindow {
    id: root

    readonly property bool closing: !panel.shown
    readonly property alias panel: panel
    property alias listView: panel.listView
    property alias pinnedIds: panel.pinnedIds
    property alias pinsEditable: panel.pinsEditable
    property alias settings: panel.settings
    property alias findSettings: panel.findSettings

    signal closeRequested()
    signal pinToggled(var app)
    signal settingChosen(var item)

    function used(app) {
        Settings.setState("launcher.usage", Usage.record(Settings.stateValue("launcher.usage", {}), app.id, Date.now()));
    }

    function close() { panel.shown = false; }
    function reopen() { panel.shown = true; }

    anchors.bottom: true
    anchors.left: true
    margins.bottom: Spacing.sm
    property real left: Spacing.md          // the launcher button's x on the shelf (the shell passes it)
    margins.left: left
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    focusable: true
    WlrLayershell.namespace: "rutile-launcher"
    implicitWidth: panel.width
    implicitHeight: panel.height
    color: "transparent"

    FileView {
        id: emojiData
        path: panel.wantsEmoji || panel.emojis.length > 0 ? (Quickshell.env("RUTILE_EMOJI_DATA") ?? "") : ""
        printErrors: false
        onLoaded: panel.emojis = Answers.parseEmoji(text())
    }

    LauncherPanel {
        id: panel
        objectName: "launcherPanel"
        apps: DesktopEntries.applications.values.map(e => ({
            type: "app", id: e.id, name: e.name, genericName: e.genericName, subtitle: e.comment,
            keywords: e.keywords, categories: e.categories,
            actions: e.actions.map(a => ({ id: a.id, name: a.name })), icon: e.icon ? Quickshell.iconPath(e.icon, true) : ""
        }))
        // read once on opening, so the results do not move under the closing motion after a launch counts
        Component.onCompleted: usage = Settings.stateValue("launcher.usage", {})
        onLaunched: app => {
            const e = DesktopEntries.byId(app.id);
            if (e) {
                e.execute();
                root.used(app);
            }
            root.close();
        }
        onActionChosen: (app, actionId) => {
            const action = DesktopEntries.byId(app.id)?.actions.find(a => a.id === actionId);
            if (action) {
                action.execute();
                root.used(app);
            }
            root.close();
        }
        onPinToggled: app => root.pinToggled(app)
        onCopyRequested: text => {
            Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", text]);
            ToastService.show("Copied " + text, { icon: "content_copy" });
            root.close();
        }
        onSettingChosen: item => {
            root.settingChosen(item);
            root.close();
        }
        onCloseRequested: root.close()
        onHidden: root.closeRequested()
    }
}
