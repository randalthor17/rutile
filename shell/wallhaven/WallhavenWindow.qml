// The Wallhaven browser's layer-shell surface (D128): centered above the shelf, as the clipboard picker, with the
// keyboard while open. The shell creates it in a LazyLoader only while open (D31); close() plays the closing motion,
// then closeRequested asks the shell to unload it. It searches as it opens, unless results are already there.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: root

    readonly property bool closing: !panel.shown
    readonly property alias panel: panel

    signal closeRequested()

    function close() { panel.shown = false; }
    function reopen() { panel.shown = true; }

    anchors.bottom: true
    margins.bottom: Spacing.sm
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    focusable: true
    WlrLayershell.namespace: "rutile-wallhaven"
    implicitWidth: panel.width
    implicitHeight: panel.height
    color: "transparent"

    Component.onCompleted: if (WallhavenService.wallpapers.length === 0) WallhavenService.search(1)

    WallhavenPanel {
        id: panel
        objectName: "wallhavenPanel"
        wallpapers: WallhavenService.wallpapers
        filters: WallhavenService.filters
        page: WallhavenService.page
        pages: WallhavenService.pages
        loading: WallhavenService.loading
        error: WallhavenService.error
        applying: WallhavenService.applying
        hasKey: WallhavenService.hasKey
        screenSize: root.screen ? Math.round(root.screen.width * root.screen.devicePixelRatio) + "x"
                                  + Math.round(root.screen.height * root.screen.devicePixelRatio) : ""
        onSearchRequested: p => WallhavenService.search(p)
        onFiltersEdited: changes => WallhavenService.setFilters(changes)
        onChosen: w => WallhavenService.apply(w)
        onCloseRequested: root.close()
        onHidden: root.closeRequested()
    }
}
