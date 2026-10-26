pragma Singleton
// niri over its IPC socket ($NIRI_SOCKET), with Quickshell's Socket: the event stream keeps `state` (NiriState.js)
// current, and requests go over a second connection, one at a time. Stands in for Quickshell's planned
// Quickshell.Niri module (PR #949, D38) behind the same small surface. Reconnects every 2 s while niri is away.
import QtQuick
import Quickshell
import Quickshell.Io
import "NiriState.js" as NiriState

Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""
    readonly property bool available: events.connected
    property var state: NiriState.empty()

    // One output's workspaces with their windows (NiriState.groups); "" for all outputs.
    function groups(output) {
        return NiriState.groups(state, output);
    }

    function focusWindow(id) {
        request(NiriState.focusWindowRequest(id));
    }

    // Move `delta` workspaces up (-1) or down (+1) on one output, stopping at the first and at niri's blank last one.
    function scrollWorkspace(output, delta) {
        const id = NiriState.neighbourWorkspace(state, output, delta);
        if (id !== null) request(NiriState.focusWorkspaceRequest(id));
    }

    property var _queue: []
    function request(line) {
        if (socketPath === "") return;
        _queue = _queue.concat([line]);
        if (!requests.connected) requests.connected = true;
    }

    Socket {
        id: events
        path: root.socketPath
        connected: root.socketPath !== ""
        onConnectedChanged: {
            if (connected) {
                write("\"EventStream\"\n");
                flush();
            } else {
                root.state = NiriState.empty();
            }
        }
        parser: SplitParser {
            onRead: line => {
                try {
                    const msg = JSON.parse(line);
                    if (!("Ok" in msg) && !("Err" in msg)) root.state = NiriState.apply(root.state, msg);
                } catch (e) {
                    console.warn("rutile: niri event not understood:", line);
                }
            }
        }
    }

    Socket {
        id: requests
        path: root.socketPath
        onConnectedChanged: {
            if (connected && root._queue.length > 0) {
                write(root._queue[0] + "\n");
                flush();
            }
        }
        // One request per connection: on the reply, drop it and go on with the next.
        parser: SplitParser {
            onRead: line => {
                root._queue = root._queue.slice(1);
                requests.connected = false;
                if (root._queue.length > 0) Qt.callLater(() => requests.connected = true);
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.socketPath !== "" && !events.connected
        onTriggered: events.connected = true
    }
}
