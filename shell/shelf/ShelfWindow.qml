// The shelf's layer-shell surface along the bottom of one screen, on the top layer, showing that screen's
// workspaces. It spans the width, so its exclusive zone (PanelWindow's default, its height) keeps windows above
// it (niri adds its gap).
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var backend
    readonly property alias shelf: shelf

    signal launcherClicked()

    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.namespace: "rutile-shelf"
    WlrLayershell.layer: WlrLayer.Top
    implicitHeight: shelf.height
    color: "transparent"

    Shelf {
        id: shelf
        anchors.left: parent.left
        anchors.right: parent.right
        pinned: root.backend.pinned
        groups: root.backend.groupsFor(root.screen?.name ?? "")
        onLaunched: app => root.backend.launch(app)
        onLauncherClicked: root.launcherClicked()
        onWindowClicked: window => root.backend.focusWindow(window)
        onWorkspaceScrolled: delta => root.backend.scrollWorkspace(root.screen?.name ?? "", delta)
    }
}
