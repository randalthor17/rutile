// The desktop widgets' layer-shell surface on one screen (plan 4.4, D81): above the wallpaper and under every
// window, in the space bars leave free. Outside edit mode it takes the pointer only on the widgets (D86), where a
// right-click edits them; elsewhere clicks go to the wallpaper. While editing it takes the pointer and the keyboard.
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
    property alias scaleText: content.scaleText
    property alias commitHandler: content.commitHandler

    signal doneRequested()
    signal addListRequested()
    signal galleryRequested()
    signal editRequested(int index)
    signal pressed()

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "rutile-widgets"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: editMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    mask: editMode ? null : onWidgets

    // the widgets' cells, from the geometry (Quickshell's Region measures an item once, with its scale)
    Region {
        id: onWidgets
        regions: cells.instances
    }
    Variants {
        id: cells
        model: content.inputRects
        Region {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height
        }
    }

    DesktopWidgets {
        id: content
        anchors.fill: parent
        onDoneRequested: root.doneRequested()
        onAddListRequested: root.addListRequested()
        onGalleryRequested: root.galleryRequested()
        onEditRequested: index => root.editRequested(index)
        onPressed: root.pressed()
    }
}
