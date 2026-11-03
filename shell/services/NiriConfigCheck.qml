// Whether niri's config.kdl includes Rutile's rutile.kdl (D72), which the user adds once: the shell's niri files
// (the colors, Settings > Input) reach niri only through it. The config is read, never written, and watched;
// `remind()` says what to add in a toast, once per run, when a setting that needs it is on and it is missing.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri"
    // null until read; true when an include line (not a comment) names rutile.kdl
    property var included: null
    property bool reminded: false
    property bool pending: false                // asked before the config was read
    property bool loadedOnce: false

    signal configChanged()                      // config.kdl changed after it was first read

    function check(text) {
        included = /^\s*include\b[^\n]*rutile\.kdl/m.test(text ?? "");
        if (pending) remind();
    }
    function remind() {
        if (included === null) {
            pending = true;
            return;
        }
        pending = false;
        if (included || reminded) return;
        reminded = true;
        ToastService.show('niri needs include optional=true "rutile.kdl" at the end of ' + dir + "/config.kdl", { icon: "info" });
    }

    FileView {
        path: root.dir + "/config.kdl"
        watchChanges: true
        printErrors: false
        blockLoading: true
        onLoaded: {
            root.check(text());
            if (root.loadedOnce) root.configChanged();
            root.loadedOnce = true;
        }
        onLoadFailed: root.check("")
        onFileChanged: reload()
    }
}
