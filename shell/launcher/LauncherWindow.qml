// The launcher's layer-shell surface: centered above the shelf (it keeps clear of the shelf's and the status
// strip's exclusive zones), keyboard focus on open. The shell creates it in a LazyLoader only while open (D31);
// close() plays the closing motion, then closeRequested asks the shell to unload it. The apps are the desktop
// entries Quickshell finds (DesktopEntries.applications: not hidden, not NoDisplay).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

PanelWindow {
    id: root

    readonly property bool closing: !panel.shown
    readonly property alias panel: panel
    property alias listView: panel.listView

    signal closeRequested()

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
            keywords: e.keywords, categories: e.categories, icon: e.icon ? Quickshell.iconPath(e.icon, true) : ""
        }))
        onLaunched: app => {
            const e = DesktopEntries.byId(app.id);
            if (e) e.execute();
            root.close();
        }
        onCloseRequested: root.close()
        onHidden: root.closeRequested()
    }
}
