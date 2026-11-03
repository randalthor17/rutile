// The shell's settings into niri (D70, D74): the parts that are on (Settings > Keyboard, mouse & touchpad;
// Accessibility's "niri's animations too") go to $XDG_CONFIG_HOME/niri/rutile-settings.kdl (NiriSettings.js),
// which niri reads through rutile.kdl; niri watches it and applies a change at once. With no part on the file is
// removed, and niri's own config is all again. It writes only when the text changes.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "NiriSettings.js" as NiriSettings

Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri"
    readonly property string path: dir + "/rutile-settings.kdl"
    readonly property bool inputOn: Settings.value("input.enabled") === true
    readonly property bool animationsOn: Settings.value("motion.niri") === true
    readonly property string text: NiriSettings.kdl({
        input: !inputOn ? null : {
            keyboardLayout: Settings.value("input.keyboardLayout") ?? "",
            repeatDelay: Settings.value("input.repeatDelay"), repeatRate: Settings.value("input.repeatRate"),
            touchpadTap: Settings.value("input.touchpadTap") === true,
            touchpadDisableWhileTyping: Settings.value("input.touchpadDisableWhileTyping") === true,
            touchpadNaturalScroll: Settings.value("input.touchpadNaturalScroll") === true,
            touchpadSpeed: Settings.value("input.touchpadSpeed"),
            mouseNaturalScroll: Settings.value("input.mouseNaturalScroll") === true,
            mouseSpeed: Settings.value("input.mouseSpeed"), mouseFlat: Settings.value("input.mouseFlat") === true
        },
        animations: animationsOn ? Motion.speed : null
    })
    property string written: "?"                // what the file has, as far as this shell knows ("?": not known)
    property string error: ""

    function sync() {
        if (text !== "") NiriConfigCheck.remind();
        if (text === written) return;
        if (text !== "") {
            file.setText(text);
            written = text;
        } else {
            remove.running = true;
        }
    }

    onTextChanged: Qt.callLater(sync)
    // Settings load synchronously, so the values are there from the start; a file left from before goes or is
    // rewritten, and so does D70's rutile-input.kdl, which nothing includes now
    Component.onCompleted: Qt.callLater(sync)

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
        command: ["rm", "-f", root.path, root.dir + "/rutile-input.kdl"]
        onExited: code => {
            if (code === 0) root.written = "";
            else root.error = "could not remove " + root.path;
        }
    }
}
