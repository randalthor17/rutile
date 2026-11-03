// The desktop widgets' layer-shell surface on one screen (plan 4.4, D81): above the wallpaper and under every
// window, in the space bars leave free. It takes no input outside edit mode, so a click or a right-click goes to
// the wallpaper; while editing it takes the pointer and the keyboard.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    readonly property alias content: content
    property alias items: content.items
    property alias specs: content.specs
    property alias available: content.available
    property alias editMode: content.editMode
    property alias columns: content.columns
    property alias commitHandler: content.commitHandler

    signal doneRequested()
    signal addListRequested()
    signal galleryRequested()

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "rutile-widgets"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: editMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    mask: editMode ? null : nothing

    Region { id: nothing }

    DesktopWidgets {
        id: content
        anchors.fill: parent
        onDoneRequested: root.doneRequested()
        onAddListRequested: root.addListRequested()
        onGalleryRequested: root.galleryRequested()
    }
}
