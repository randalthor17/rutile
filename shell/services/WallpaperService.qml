pragma Singleton
// The wallpaper (plan 2.9): the wallpaper.path setting, which WallpaperWindow shows on every screen and the lock
// screen blurs. When it changes (set(), IPC, or settings.json edited by hand) and wallpaper.palette is on, the
// palette is rendered from it (tools/palette.py --image, matugen) into the file PaletteWatcher reads, so the colors
// follow. The path rendered last is remembered in state.json, so a restart does not render again.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string path: Settings.value("wallpaper.path") ?? ""
    readonly property bool paletteFollows: Settings.value("wallpaper.palette") === true
    readonly property string palettePath: Quickshell.env("RUTILE_PALETTE")
        || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/rutile/palette.json")
    // RUTILE_PALETTE_TOOL: tests only (a stand-in that logs instead of running matugen)
    readonly property string paletteTool: Quickshell.env("RUTILE_PALETTE_TOOL") || Quickshell.shellDir + "/../tools/palette.py"
    property string lastError: ""

    // false when the path is not absolute or the setting is set in Nix
    function set(p) {
        if (p !== "" && !p.startsWith("/")) return false;
        return Settings.set("wallpaper.path", p);
    }

    function renderPalette() {
        if (!paletteFollows || path === "" || renderer.running) return;
        if (Settings.stateValue("wallpaper.paletteFrom", "") === path) return;
        renderer.target = path;
        renderer.command = ["python3", paletteTool, "render", "--image", path, "--out", palettePath];
        renderer.running = true;
    }
    onPathChanged: Qt.callLater(renderPalette)
    onPaletteFollowsChanged: Qt.callLater(renderPalette)
    Component.onCompleted: Qt.callLater(renderPalette)

    Process {
        id: renderer
        property string target: ""
        stderr: StdioCollector { id: errors }
        onExited: code => {
            if (code === 0) {
                root.lastError = "";
                Settings.setState("wallpaper.paletteFrom", target);
            } else {
                root.lastError = errors.text.trim() || ("palette.py exited " + code);
                console.warn("rutile: no palette from the wallpaper: " + root.lastError);
            }
            if (target !== root.path) root.renderPalette();   // it changed meanwhile
        }
    }
}
