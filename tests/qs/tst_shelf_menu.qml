// A shelf button's right-click menu (D72) with the fixture apps: a pin offers open, its desktop actions and Unpin;
// a window of an app with a desktop entry offers a new window, Pin and Close; choosing runs it (the desktop action
// through fake-app, the pin into shelf.pins). The Shelf page's backend shows the same pins with names, takes ids
// with ".desktop", and goes back to the default.
// env XDG_DATA_DIRS=@WS@/apps
// env XDG_DATA_HOME=@WS@/no-user-apps
// env PATH=@WS@/bin:@PATH@
// env FAKE_APP_LOG=@WS@/apps.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.shelf

ShellRoot {
    id: root
    property int stage: 0
    QsTest { id: t }
    ShelfBackend { id: backend }
    Loader {
        id: page
        source: Qt.resolvedUrl("settingsapp/pages/ShelfPinsBackend.qml")
    }
    FileView {
        id: log
        path: Quickshell.env("FAKE_APP_LOG")
        printErrors: false
        blockLoading: true
    }
    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            const p = page.item;
            switch (root.stage) {
            case 0: {
                if (!p) return;
                t.compare(backend.pinnedIds.join(), "org.gnome.Nautilus,firefox,foot", "the fixture defaults");
                t.compare(p.pins.map(x => x.name).join(), "Files,Firefox,Foot", "the page names them");
                t.verify(p.isDefault);
                const items = backend.menuFor({ app: { id: "firefox" } });
                t.compare(items.map(i => i.separator ? "-" : i.text).join(), "Open,New Private Window,-,Unpin");
                backend.runMenu({ app: { id: "firefox" } }, "action:0");
                const w = backend.menuFor({ window: { id: 7, appId: "firefox" } });
                t.compare(w.map(i => i.separator ? "-" : i.id).join(), "open,action:0,-,unpin,-,close", "a window of a pinned app");
                const odd = backend.menuFor({ window: { id: 8, appId: "no-such-app" } });
                t.compare(odd.map(i => i.id).join(), "close", "no desktop entry: close only");
                backend.runMenu({ app: { id: "firefox" } }, "unpin");
                break;
            }
            case 1:
                t.compare(backend.pinnedIds.join(), "org.gnome.Nautilus,foot", "unpinned from the menu");
                t.verify(!p.isDefault);
                backend.runMenu({ window: { id: 7, appId: "firefox" } }, "pin");
                break;
            case 2:
                t.compare(backend.pinnedIds.join(), "org.gnome.Nautilus,foot,firefox", "pinned from a window's menu");
                log.reload();
                t.verify(log.text().indexOf("firefox --private-window") >= 0, "the desktop action ran: " + log.text());
                p.setPins(["firefox.desktop", "foot"]);
                break;
            case 3:
                t.compare(p.pins.map(x => x.name).join(), "Firefox,Foot", "ids with .desktop");
                t.compare(backend.pinned.map(x => x.name).join(), "Firefox,Foot", "and the shelf shows them");
                p.reset();
                break;
            case 4:
                t.verify(p.isDefault);
                t.compare(backend.pinnedIds.join(), "org.gnome.Nautilus,firefox,foot", "back to the default");
                t.done();
                break;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
