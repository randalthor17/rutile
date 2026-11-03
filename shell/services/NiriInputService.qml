// Settings > Input into niri (D70): while `input.enabled` is on, the input settings go to
// $XDG_CONFIG_HOME/niri/rutile-input.kdl (NiriInput.js), which the home-manager module includes after niri's own
// config; niri watches it and applies a change at once. Off removes the file, and niri's own config is all again.
// It writes only when the text changes, and nothing at all while off and no file was ever written.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NiriInput.js" as NiriInput

Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                                    + "/niri/rutile-input.kdl"
    readonly property bool enabled: Settings.value("input.enabled") === true
    readonly property string text: NiriInput.kdl({
        repeatDelay: Settings.value("input.repeatDelay"), repeatRate: Settings.value("input.repeatRate"),
        touchpadTap: Settings.value("input.touchpadTap") === true,
        touchpadNaturalScroll: Settings.value("input.touchpadNaturalScroll") === true,
        touchpadSpeed: Settings.value("input.touchpadSpeed"),
        mouseNaturalScroll: Settings.value("input.mouseNaturalScroll") === true,
        mouseSpeed: Settings.value("input.mouseSpeed"), mouseFlat: Settings.value("input.mouseFlat") === true
    })
    property string written: ""                 // what the file has, as far as this shell knows
    property string error: ""

    function sync() {
        if (enabled) NiriConfigCheck.remind();
        if (enabled && text !== written) {
            file.setText(text);
            written = text;
        } else if (!enabled && written !== "") {
            remove.running = true;
        }
    }

    onEnabledChanged: Qt.callLater(sync)
    onTextChanged: Qt.callLater(sync)
    // Settings load synchronously, so the values are there from the start
    Component.onCompleted: {
        // a file left from before (the switch turned off while the shell was not running) goes too
        if (!enabled) written = "?";
        Qt.callLater(sync);
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
            else root.error = "could not remove " + root.path;
        }
    }
}
