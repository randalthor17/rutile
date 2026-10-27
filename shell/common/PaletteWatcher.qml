// Feeds palette.json into the Colors singleton and reloads it when the file changes.
// Needs Quickshell, so it is not covered by the offscreen QML tests; instantiate
// one of these in shell.qml (the gallery does, plan item 1.7).
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // RUTILE_PALETTE overrides; default is $XDG_CACHE_HOME/rutile/palette.json.
    property string path: Quickshell.env("RUTILE_PALETTE")
        || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/rutile/palette.json")

    property bool missing: false

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.missing = false;
            Colors.load(text());
        }
        onLoadFailed: error => {
            if (!root.missing) console.warn("rutile: cannot read palette " + root.path + " (" + error + ")");
            root.missing = true;
        }
    }

    // FileView watches only a file that exists, so a palette written after the shell started (the first render)
    // went unnoticed until a restart (Quickshell 0.3.2). While there is none, look again now and then.
    Timer {
        interval: 3000
        repeat: true
        running: root.missing
        onTriggered: file.reload()
    }
}
