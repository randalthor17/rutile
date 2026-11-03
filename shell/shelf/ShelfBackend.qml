// The shelf's data on this system: the pinned desktop entries (ShelfApps.pins, from the shelf.pins setting) and the open windows by workspace from niri (NiriService). Without niri,
// Quickshell's ToplevelManager (wlr-foreign-toplevel) gives the windows ungrouped. The shell makes one for all
// screens; each shelf asks groupsFor() its own output.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import "ShelfApps.js" as ShelfApps

QtObject {
    id: root

    readonly property var pinnedIds: {
        void DesktopEntries.applications.values;        // look again when the installed apps change
        return ShelfApps.pins(Settings.value("shelf.pins"), id => !!DesktopEntries.byId(id));
    }
    // [{id, name, icon}], the icon as an image URL ("" when the theme has none)
    readonly property var pinned: {
        void DesktopEntries.applications.values;
        return pinnedIds.map(id => DesktopEntries.byId(id)).filter(e => !!e)
                        .map(e => ({ id: e.id, name: e.name, icon: iconUrl(e.icon) }));
    }
    // Pin and Unpin save the shelf.pins setting, starting from the pins shown; not while Nix sets them (D45).
    readonly property bool pinsEditable: !Settings.isManaged("shelf.pins")
    function togglePin(id) {
        return Settings.set("shelf.pins", ShelfApps.togglePin(pinnedIds, id));
    }

    readonly property bool niri: NiriService.available
    readonly property var toplevels: ToplevelManager.toplevels.values

    function iconUrl(name) {
        return name ? Quickshell.iconPath(name, true) : "";
    }

    function lookup(appId) {
        const e = appId ? DesktopEntries.heuristicLookup(appId) : null;
        return e ? { name: e.name, icon: iconUrl(e.icon) } : null;
    }

    // One output's workspaces with their windows (ShelfApps.decorate); all windows in one group without niri.
    function groupsFor(output) {
        const groups = niri ? NiriService.groups(output)
                            : ShelfApps.ungrouped(toplevels.map(t => ({ appId: t.appId, title: t.title, activated: t.activated })));
        return ShelfApps.decorate(groups, appId => lookup(appId));
    }

    // A button's right-click menu (D72): `target` is {app} (a pin) or {window}.
    function entryOf(target) {
        if (target.window) return target.window.appId ? DesktopEntries.heuristicLookup(target.window.appId) : null;
        return DesktopEntries.byId(target.app.id);
    }
    function menuFor(target) {
        const e = entryOf(target);
        return ShelfApps.menuItems({ window: !!target.window, entry: !!e, actions: e ? e.actions.map(a => a.name) : [],
                                     pinned: !!e && pinnedIds.indexOf(e.id) >= 0, editable: pinsEditable });
    }
    function runMenu(target, id) {
        const e = entryOf(target);
        if (id === "open") e?.execute();
        else if (id.startsWith("action:")) e?.actions[Number(id.slice(7))]?.execute();
        else if ((id === "pin" || id === "unpin") && e) togglePin(e.id);
        else if (id === "close" && target.window) closeWindow(target.window);
    }
    function closeWindow(window) {
        if (niri) NiriService.closeWindow(window.id);
        else if (toplevels[window.id]) toplevels[window.id].close();
    }

    function launch(app) {
        const e = DesktopEntries.byId(app.id);
        if (e) e.execute();
    }

    // The wheel over a screen's shelf: niri's workspaces on that output (nothing without niri).
    function scrollWorkspace(output, delta) {
        if (niri) NiriService.scrollWorkspace(output, delta);
    }

    function focusWindow(window) {
        if (niri) NiriService.focusWindow(window.id);
        else if (toplevels[window.id]) toplevels[window.id].activate();
    }
}
