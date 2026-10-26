// A popup (dropdown, menu) created only while it shows (D31), with the shared PopupMotion (D43): `open` loads it and
// grows it in from `origin`; closing plays the motion out, then unloads it.
//     PopupLoader { open: root.menuOpen; origin: Item.TopRight; sourceComponent: Menu {} }
import QtQuick

Loader {
    id: root

    property bool open: false
    property int origin: Item.Top
    readonly property alias motion: popupMotion

    active: open || popupMotion.visible

    PopupMotion {
        id: popupMotion
        target: root.item as Item
        shown: root.open
        origin: root.origin
    }
}
