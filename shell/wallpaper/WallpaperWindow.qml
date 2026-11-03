// The wallpaper's layer-shell surface on one screen (plan 2.9): the whole screen, on the background layer, under
// every window and the shelf, taking no keyboard and no space from windows. A right-click on it opens the desktop's
// menu (D81): edit the widgets, change the wallpaper; it closes on a choice, a click elsewhere, or Escape.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services

PanelWindow {
    id: root

    readonly property alias view: view
    property bool menuOpen: false

    signal editWidgetsRequested()
    signal wallpaperSettingsRequested()
    signal pressed()                        // any press: the shell closes its popups (a click outside them, D90)

    function openMenu(x, y) {
        menu.at = Qt.point(x, y);
        menuOpen = true;
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rutile-wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"

    WallpaperView {
        id: view
        anchors.fill: parent
        path: WallpaperService.path
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.pressed()
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.openMenu(mouse.x, mouse.y);
            else
                root.menuOpen = false;
        }
    }
    Item {
        anchors.fill: parent
        focus: root.menuOpen
        Keys.onEscapePressed: root.menuOpen = false
    }
    PopupLoader {
        id: menu
        property point at: Qt.point(0, 0)
        readonly property bool leftward: at.x + (item?.width ?? 0) > root.width
        readonly property bool upward: at.y + (item?.height ?? 0) > root.height
        open: root.menuOpen
        origin: upward ? (leftward ? Item.BottomRight : Item.BottomLeft) : (leftward ? Item.TopRight : Item.TopLeft)
        x: leftward ? at.x - (item?.width ?? 0) : at.x
        y: upward ? at.y - (item?.height ?? 0) : at.y
        sourceComponent: Menu {
            items: [{ id: "widgets", text: "Edit widgets", icon: "widgets" },
                    { id: "wallpaper", text: "Change wallpaper", icon: "wallpaper" }]
            itemPrefix: "desktopMenu_"
            onChosen: id => {
                root.menuOpen = false;
                if (id === "widgets") root.editWidgetsRequested();
                else root.wallpaperSettingsRequested();
            }
        }
    }
}
