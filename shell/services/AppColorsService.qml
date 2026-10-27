pragma Singleton
// Other apps in the shell's colors (D52): while `appColors.enabled` is on, the apps switched on under it are themed
// by tools/apptheme.py from the palette, again whenever the palette changes (a new wallpaper); an app switched off,
// or the main switch, takes its colors back out. Everything is off by default, and with nothing on and nothing
// themed before (state.json's appColors.synced) the tool is never even started.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var apps: ["gtk", "qt", "kitty", "ghostty", "btop", "nvim", "firefox"]
    readonly property bool enabled: Settings.value("appColors.enabled") === true
    readonly property var wanted: enabled ? apps.filter(a => Settings.value("appColors." + a) === true) : []
    readonly property var synced: Settings.stateValue("appColors.synced", [])
    readonly property string palettePath: WallpaperService.palettePath
    // RUTILE_APPTHEME_TOOL: tests only (a stand-in that logs instead of writing to the user's apps)
    readonly property string tool: Quickshell.env("RUTILE_APPTHEME_TOOL") || Quickshell.shellDir + "/../tools/apptheme.py"
    property string lastError: ""
    property int runs: 0

    function schedule() {
        if (wanted.length === 0 && synced.length === 0) return;   // nothing on, nothing to take back
        debounce.restart();
    }
    function sync() {
        if (runner.running) {
            again = true;
            return;
        }
        runner.target = wanted.slice();
        runner.command = ["python3", tool, "sync", "--palette", palettePath, "--apps", runner.target.join(",")];
        runner.running = true;
    }
    property bool again: false

    onWantedChanged: schedule()
    Component.onCompleted: schedule()

    // Several switches flipped together, or a palette written in steps, make one run.
    Timer {
        id: debounce
        interval: 400
        onTriggered: root.sync()
    }

    // The palette changes with the wallpaper: the apps follow.
    FileView {
        path: root.palettePath
        watchChanges: true
        printErrors: false
        onFileChanged: root.schedule()
    }

    Process {
        id: runner
        property var target: []
        stderr: StdioCollector { id: errors }
        onExited: code => {
            root.runs++;
            if (code === 0) {
                root.lastError = "";
                Settings.setState("appColors.synced", target);
            } else {
                root.lastError = errors.text.trim() || ("apptheme.py exited " + code);
                console.warn("rutile: other apps' colors: " + root.lastError);
            }
            if (root.again || JSON.stringify(target) !== JSON.stringify(root.wanted)) {
                root.again = false;
                root.schedule();
            }
        }
    }
}
