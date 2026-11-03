// The Display page's backend (DisplayPage.qml has the interface): niri's outputs through `niri msg` (the niri on
// PATH talks to $NIRI_SOCKET). The window loads it only while the page is open (D31); it reads the outputs then,
// and again after each change. Changes go through `niri msg output`, at once; NiriDisplayService then keeps the
// output as niri has it, and puts it first again whenever niri starts or its config changes (D74).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Item {
    id: root

    property bool available: false
    property var outputs: []                    // niri's JSON, by name
    property string error: ""
    property var _queue: []
    property var _changed: ({})                 // outputs changed since the last read: kept once read again
    // the outputs whose choices the shell keeps (D74)
    readonly property var kept: Object.keys(NiriDisplayService.kept)

    function refresh() {
        if (!query.running) query.running = true;
    }
    // `niri msg output NAME ARGS...`
    function command(name, args) {
        _queue = _queue.concat([["niri", "msg", "output", name].concat(args)]);
        const c = Object.assign({}, _changed);
        c[name] = true;
        _changed = c;
        next();
    }
    function next() {
        if (act.running || _queue.length === 0) return;
        act.command = _queue[0];
        _queue = _queue.slice(1);
        act.running = true;
    }
    // back to niri's own config for that output
    function reset(name) {
        NiriDisplayService.forget(name);
        refreshLater.restart();
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
                    if (!act.running && root._queue.length === 0) {
                        for (const o of root.outputs) if (root._changed[o.name]) NiriDisplayService.remember(o);
                        root._changed = ({});
                    }
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
    // niri applies the config change from removing a kept output a moment after the file is written
    Timer {
        id: refreshLater
        interval: 500
        onTriggered: root.refresh()
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
