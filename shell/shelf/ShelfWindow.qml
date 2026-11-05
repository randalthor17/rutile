// The shelf's layer-shell surface along the bottom of one screen, on the top layer, showing that screen's
// workspaces. It spans the width, so its exclusive zone (PanelWindow's default, its height) keeps windows above
// it (niri adds its gap). A button's tooltip (D106) is a surface of its own above the shelf, loaded while shown.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var backend
    readonly property alias shelf: shelf
    readonly property alias tooltip: tooltipLoader

    signal launcherClicked()
    signal pressed()
    signal menuRequested(var target, real x)    // a button's right click (Shelf.menuRequested)

    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.namespace: "rutile-shelf"
    WlrLayershell.layer: WlrLayer.Top
    implicitHeight: shelf.height
    color: "transparent"

    Shelf {
        id: shelf
        onPressed: root.pressed()
        anchors.left: parent.left
        anchors.right: parent.right
        pinned: root.backend.pinned
        groups: root.backend.groupsFor(root.screen?.name ?? "")
        onLaunched: app => root.backend.launch(app)
        onLauncherClicked: root.launcherClicked()
        onMenuRequested: (target, x) => root.menuRequested(target, x)
        onWindowClicked: window => root.backend.focusWindow(window)
        onWorkspaceScrolled: delta => root.backend.scrollWorkspace(root.screen?.name ?? "", delta)
    }

    // the last text stays while the tooltip shrinks away
    property string tooltipText: ""
    readonly property bool tooltipWanted: shelf.tooltipText !== ""
    onTooltipWantedChanged: if (tooltipWanted) {
        tooltipText = shelf.tooltipText;
        tooltipLoader.active = true;
    }
    Connections {
        target: shelf
        function onTooltipTextChanged() {
            if (shelf.tooltipText !== "") root.tooltipText = shelf.tooltipText;
        }
    }
    LazyLoader {
        id: tooltipLoader
        ShelfTooltipWindow {
            screen: root.screen
            text: root.tooltipText
            centerX: shelf.tooltipX
            shelfHeight: shelf.height
            shown: root.tooltipWanted
            onGone: tooltipLoader.active = false
        }
    }
}
