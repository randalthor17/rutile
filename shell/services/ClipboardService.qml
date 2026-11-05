// Clipboard history (D119) through cliphist: while `clipboard.history` is on, two wl-paste watchers store each copy
// (text, and images) in cliphist's database, as cliphist's README sets it up; a watcher that stops is started
// again. list() reads the history into `entries` (newest first), copy() puts one back on the clipboard, remove()
// and wipe() forget. The picker (shell/clipboard) asks for these; the shell pastes nothing itself.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../clipboard/Clipboard.js" as Clipboard

Singleton {
    id: root

    readonly property bool enabled: Settings.value("clipboard.history") !== false
    property var entries: []
    property bool reading: false

    function list() {
        if (lister.running) return;
        reading = true;
        lister.running = true;
    }
    function copy(entry) {
        Quickshell.execDetached(Clipboard.copyCommand(entry.line));
    }
    function remove(entry) {
        entries = entries.filter(e => e.line !== entry.line);
        Quickshell.execDetached(Clipboard.deleteCommand(entry.line));
    }
    function wipe() {
        entries = [];
        Quickshell.execDetached(["cliphist", "wipe"]);
    }

    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = Clipboard.parse(text);
                root.reading = false;
            }
        }
        onExited: root.reading = false
    }

    Process {
        id: textWatch
        command: ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]
        running: root.enabled
    }
    Process {
        id: imageWatch
        command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]
        running: root.enabled
    }
    // a watcher that stopped (the compositor restarted, wl-paste failed) is started again
    Timer {
        interval: 5000
        repeat: true
        running: root.enabled && (!textWatch.running || !imageWatch.running)
        onTriggered: {
            textWatch.running = true;
            imageWatch.running = true;
        }
    }
}
