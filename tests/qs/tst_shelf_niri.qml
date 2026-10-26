// ShelfBackend with niri (the fake socket, tests/qs/bin/fake-niri) and the fixture apps: windows come grouped by
// workspace, one per window, named from their desktop entries; a click focuses that window over niri.
// env NIRI_SOCKET=@WS@/niri.sock
// env PATH=@WS@/bin:@PATH@
// env XDG_DATA_DIRS=@WS@/apps
// env XDG_DATA_HOME=@WS@/no-user-apps
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.shelf

ShellRoot {
    id: root
    QsTest { id: t }
    ShelfBackend { id: backend }
    readonly property string ws: Quickshell.env("NIRI_SOCKET").replace(/\/niri\.sock$/, "")

    Process {
        running: true
        command: ["fake-niri", Quickshell.env("NIRI_SOCKET"), root.ws + "/requests.log"]
    }
    FileView {
        id: requestLog
        path: root.ws + "/requests.log"
        blockLoading: true
        printErrors: false
    }

    property int waited: 0
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            root.waited += interval;
            if (backend.groupsFor("DP-1").length < 2 && root.waited < 10000) return;
            stop();
            t.verify(backend.niri, "niri is there");
            const g = backend.groupsFor("DP-1");
            t.compare(g.map(x => x.idx).join(), "1,2", "by workspace");
            t.compare(g[0].windows.map(w => w.name).join(), "Firefox,kitty", "named from the entry, else the app id");
            t.compare(g[1].windows.map(w => w.name).join(), "Foot", "one per window");
            t.compare(backend.groupsFor("HDMI-A-1").length, 0, "another output has none");
            backend.focusWindow(g[0].windows[1]);
            check.start();
        }
    }
    Timer {
        id: check
        interval: 1500
        onTriggered: {
            requestLog.reload();
            t.compare(requestLog.text().trim(), '{"Action":{"FocusWindow":{"id":10}}}', "focus that window over niri");
            t.done();
        }
    }
}
