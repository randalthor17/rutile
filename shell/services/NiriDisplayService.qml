// Settings > Display's choices kept and put first (D74). niri's own config would win over an included output
// section (`output` sections are not merged: the first one for an output applies), so the shell applies what the
// Display page chose with `niri msg output` when it starts and whenever niri's config.kdl changes; niri keeps such
// a change until that output's config changes. The choices (an entry per output name) are kept in state.json and
// also written to $XDG_CONFIG_HOME/niri/rutile-display.kdl, which niri reads through rutile.kdl, so they hold
// while the shell is not running for outputs niri's own config leaves alone.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NiriDisplay.js" as Display

Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                                    + "/niri/rutile-display.kdl"
    readonly property var kept: Settings.stateValue("display.outputs", {})
    readonly property string text: Display.entriesKdl(kept)
    property string written: "?"
    property string error: ""
    property var _queue: []
    property int applied: 0                     // how many times the kept choices were applied (tests)

    // An output as niri now has it (its JSON), after the Display page changed it.
    function remember(o) {
        const k = Object.assign({}, kept);
        k[o.name] = Display.entry(o);
        Settings.setState("display.outputs", k);
    }
    // Back to niri's own config for this output (from niri's next config change or restart: niri keeps a
    // `niri msg` change until then when its own config sets that output).
    function forget(name) {
        const k = Object.assign({}, kept);
        delete k[name];
        Settings.setState("display.outputs", k);
    }
    // Every kept choice, through `niri msg output`; outputs not connected just fail.
    function apply() {
        if (!Quickshell.env("NIRI_SOCKET")) return;
        const q = [];
        for (const name of Object.keys(kept))
            for (const args of Display.commands(kept[name])) q.push(["niri", "msg", "output", name].concat(args));
        _queue = _queue.concat(q);
        applied++;
        next();
    }
    function next() {
        if (act.running || _queue.length === 0) return;
        act.command = _queue[0];
        _queue = _queue.slice(1);
        act.running = true;
    }
    function sync() {
        if (text === written) return;
        if (text !== "") {
            file.setText(text);
            written = text;
        } else {
            remove.running = true;
        }
    }

    onTextChanged: Qt.callLater(sync)
    Component.onCompleted: {
        Qt.callLater(sync);
        Qt.callLater(apply);
    }
    // the user's config changed: niri may have put an output back to it
    Connections {
        target: NiriConfigCheck
        function onConfigChanged() { root.apply(); }
    }

    Process {
        id: act
        onExited: root.next()
    }
    FileView {
        id: file
        path: root.path
        blockLoading: false
        printErrors: false
        onSaveFailed: err => root.error = "could not write " + root.path + ": " + FileViewError.toString(err)
        onSaved: root.error = ""
    }
    Process {
        id: remove
        command: ["rm", "-f", root.path]
        onExited: code => {
            if (code === 0) root.written = "";
        }
    }
}
