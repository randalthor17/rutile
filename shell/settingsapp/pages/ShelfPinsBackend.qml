// The Shelf page's backend (ShelfPage.qml has the interface): the shelf.pins setting with each pin's name and icon
// from its desktop entry. The window loads it only while the page is open (D31).
import QtQuick
import Quickshell
import qs.services
import "../../shelf/ShelfApps.js" as ShelfApps

Item {
    id: root

    readonly property bool managed: Settings.isManaged("shelf.pins")
    readonly property bool isDefault: !Array.isArray(Settings.value("shelf.pins"))
    readonly property var ids: {
        void DesktopEntries.applications.values;        // look again when the installed apps change
        return ShelfApps.pins(Settings.value("shelf.pins"), id => !!DesktopEntries.byId(id));
    }
    // [{id, name, icon (an image URL or ""), installed}]
    readonly property var pins: {
        void DesktopEntries.applications.values;
        return ids.map(id => {
            const e = DesktopEntries.byId(id);
            return { id: id, name: e ? e.name : id, icon: e && e.icon ? Quickshell.iconPath(e.icon, true) : "", installed: !!e };
        });
    }

    function setPins(list) {
        return Settings.set("shelf.pins", list);
    }
    function reset() {
        return Settings.reset("shelf.pins");
    }
}
