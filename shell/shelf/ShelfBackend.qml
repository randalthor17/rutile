// The shelf's apps on this system: the pinned desktop entries (ShelfApps.pins; RUTILE_SHELF_PINS="id,id" sets
// them until saved settings, plan 2.5) and the compositor's windows from Quickshell's ToplevelManager
// (wlr-foreign-toplevel, which niri has), combined by ShelfApps.build(). The shell makes one for all screens.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "ShelfApps.js" as ShelfApps

QtObject {
    id: root

    readonly property var pinnedIds: {
        void DesktopEntries.applications.values;        // look again when the installed apps change
        return ShelfApps.pins(Quickshell.env("RUTILE_SHELF_PINS") ?? "", id => !!DesktopEntries.byId(id));
    }
    readonly property var toplevels: ToplevelManager.toplevels.values
    readonly property var windows: toplevels.map(t => ({ appId: t.appId, activated: t.activated }))

    function entryData(e) {
        return { id: e.id, name: e.name, icon: e.icon, startupClass: e.startupClass };
    }

    // ShelfApps.build() items, with the icon as an image URL ("" when the theme has none).
    readonly property var items: {
        void DesktopEntries.applications.values;
        const pinned = pinnedIds.map(id => DesktopEntries.byId(id)).filter(e => !!e).map(e => entryData(e));
        const lookup = appId => {
            const e = DesktopEntries.heuristicLookup(appId);
            return e ? entryData(e) : null;
        };
        return ShelfApps.build(pinned, windows, lookup).map(it => Object.assign(it, {
            icon: it.icon ? Quickshell.iconPath(it.icon, true) : ""
        }));
    }

    // A running app: bring its next window forward. Otherwise start it.
    function open(item) {
        if (item.running) {
            const i = ShelfApps.nextWindow(item, windows);
            if (i >= 0) toplevels[i].activate();
            return;
        }
        const e = DesktopEntries.byId(item.id);
        if (e) e.execute();
    }
}
