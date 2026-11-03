// The widget files behind the desktop grid (plan 4.4, D81). Each file in `paths` is read once and watched, so every
// screen shows the same spec and a saved edit shows at once; `specs` holds them (path: spec, or null when it cannot
// be read or is not JSON). `scan()` lists what Add offers in `available`: the user's own widgets, in
// $XDG_CONFIG_HOME/rutile/widgets, then the examples that come with the shell.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "Desktop.js" as Desktop

Scope {
    id: root

    property var paths: []
    property var specs: ({})
    property var available: []
    readonly property string userDir: Settings.configDir + "/widgets"
    readonly property string examplesDir: {
        const shellDir = String(Quickshell.shellDir).replace(/\/+$/, "");
        return shellDir.substring(0, shellDir.lastIndexOf("/")) + "/widgets/examples";
    }

    function put(path, spec) {
        const s = Object.assign({}, specs);
        s[path] = spec;
        specs = s;
    }
    function scan() {
        lister.running = false;
        lister.running = true;
    }
    onPathsChanged: {
        const s = {};
        for (const p of paths) if (p in specs) s[p] = specs[p];
        specs = s;
    }

    Instantiator {
        model: root.paths
        delegate: FileView {
            id: file
            required property string modelData
            path: modelData
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: root.put(file.modelData, Desktop.parse(file.text()))
            onLoadFailed: root.put(file.modelData, null)
        }
    }

    Process {
        id: lister
        command: ["sh", "-c", 'for d in "$@"; do for f in "$d"/*.json; do [ -f "$f" ] || continue; ' +
                  'printf "\\036%s\\037" "$f"; cat "$f"; done; done', "sh", root.userDir, root.examplesDir]
        stdout: StdioCollector { onStreamFinished: root.available = Desktop.scanned(text) }
    }
}
