// The Display page's backend (DisplayPage.qml has the interface): niri's outputs through `niri msg` (the niri on
// PATH talks to $NIRI_SOCKET). The window loads it only while the page is open (D31); it reads the outputs then,
// and again after each change. Changes go through `niri msg output`, which lasts until niri restarts or its
// config changes the output again; `copy` puts text (the KDL to keep them) on the clipboard.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool available: false
    property var outputs: []                    // niri's JSON, by name
    property string error: ""
    property var _queue: []

    function refresh() {
        if (!query.running) query.running = true;
    }
    // `niri msg output NAME ARGS...`
    function command(name, args) {
        _queue = _queue.concat([["niri", "msg", "output", name].concat(args)]);
        next();
    }
    function next() {
        if (act.running || _queue.length === 0) return;
        act.command = _queue[0];
        _queue = _queue.slice(1);
        act.running = true;
    }
    function copy(text) {
        Quickshell.clipboardText = text;
    }

    Component.onCompleted: refresh()

    Process {
        id: query
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const all = JSON.parse(text);
                    root.outputs = Object.values(all).sort((a, b) => a.name.localeCompare(b.name));
                    root.available = true;
                } catch (e) {
                    root.available = false;
                    root.outputs = [];
                }
            }
        }
        onExited: code => {
            if (code !== 0) root.available = false;
        }
    }
    Process {
        id: act
        stderr: StdioCollector {
            onStreamFinished: root.error = text.trim()
        }
        onExited: code => {
            if (code === 0) root.error = "";
            root.refresh();
            root.next();
        }
    }
}
