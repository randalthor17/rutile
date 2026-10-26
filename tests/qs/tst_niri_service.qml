// NiriService against a fake niri socket (tests/qs/bin/fake-niri): it connects once the socket appears, follows
// the event stream, and sends focus requests one per connection.
// env NIRI_SOCKET=@WS@/niri.sock
// env PATH=@WS@/bin:@PATH@
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    QsTest { id: t }
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

    // Wait (up to 10 s) for the connection and the window that opens half a second after the snapshots.
    property int waited: 0
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            root.waited += interval;
            if (NiriService.groups("DP-1").length < 2 && root.waited < 10000) return;
            stop();
            t.verify(NiriService.available, "connected (after the fake socket appeared: it retries)");
            const g = NiriService.groups("DP-1");
            t.compare(g.map(x => x.idx).join(), "1,2", "workspaces with windows");
            t.compare(g[0].windows.map(w => w.appId).join(), "firefox,kitty", "layout order");
            t.compare(g[1].windows.map(w => w.appId).join(), "foot", "a window opened later");
            t.verify(g[0].windows[1].focused, "focus");
            NiriService.focusWindow(11);
            NiriService.focusWindow(12);
            NiriService.scrollWorkspace("DP-1", -1);       // already the first: nothing
            NiriService.scrollWorkspace("DP-1", 5);        // past the last: the blank workspace 3
            check.start();
        }
    }
    Timer {
        id: check
        interval: 1500
        onTriggered: {
            requestLog.reload();
            t.compare(requestLog.text().trim(), '{"Action":{"FocusWindow":{"id":11}}}\n{"Action":{"FocusWindow":{"id":12}}}\n'
                      + '{"Action":{"FocusWorkspace":{"reference":{"Id":3}}}}', "the requests, in order");
            t.done();
        }
    }
}
