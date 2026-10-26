// The launcher's layer-shell surface: centered above the shelf (it keeps clear of the shelf's and the status
// strip's exclusive zones), keyboard focus on open. The shell creates it in a LazyLoader only while open (D31);
// close() plays the closing motion, then closeRequested asks the shell to unload it. The apps are the desktop
// entries Quickshell finds (DesktopEntries.applications: not hidden, not NoDisplay). Each app opened from here
// counts toward its usage (state.json's `launcher.usage`, Usage.js); Pin and Unpin go to the shell (`pinToggled`).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services
import "Usage.js" as Usage

PanelWindow {
    id: root

    readonly property bool closing: !panel.shown
    readonly property alias panel: panel
    property alias listView: panel.listView
    property alias pinnedIds: panel.pinnedIds
    property alias pinsEditable: panel.pinsEditable

    signal closeRequested()
    signal pinToggled(var app)

    function used(app) {
        Settings.setState("launcher.usage", Usage.record(Settings.stateValue("launcher.usage", {}), app.id, Date.now()));
    }

    function close() { panel.shown = false; }
    function reopen() { panel.shown = true; }

    anchors.bottom: true
    margins.bottom: Spacing.sm
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    focusable: true
    WlrLayershell.namespace: "rutile-launcher"
    implicitWidth: panel.width
    implicitHeight: panel.height
    color: "transparent"

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
        onCloseRequested: root.close()
        onHidden: root.closeRequested()
    }
}
