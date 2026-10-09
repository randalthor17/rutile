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

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: Colors.load(text())
        onLoadFailed: error => console.warn("rutile: cannot read palette " + root.path + " (" + error + ")")
    }
}
