pragma Singleton
// The wallpaper (plan 2.9): the wallpaper.path setting, which WallpaperWindow shows on every screen and the lock
// screen blurs. When it changes (set(), IPC, or settings.json edited by hand) and wallpaper.palette is on, the
// palette is rendered from it into the file PaletteWatcher reads, so the colors follow: matugen with the image
// (its dominant color), checked as tools/palette.py checks it (Palette.js), then written atomically; a failed or
// invalid render leaves the palette as it was. No Python (D53). The path rendered last is remembered in
// state.json, so a restart does not render again.
import QtQuick
import Quickshell
import Quickshell.Io
import "Files.js" as Files
import "Palette.js" as Palette

Singleton {
    id: root

    readonly property string path: Settings.value("wallpaper.path") ?? ""
    readonly property bool paletteFollows: Settings.value("wallpaper.palette") === true
    readonly property string palettePath: Quickshell.env("RUTILE_PALETTE")
        || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/rutile/palette.json")
    readonly property string themeDir: Quickshell.shellDir + "/../theme"
    // RUTILE_MATUGEN: tests only (a stand-in that logs and writes a fixture instead of running matugen)
    readonly property string matugen: Quickshell.env("RUTILE_MATUGEN") || "matugen"
    readonly property string workDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rutile-palette-" + Quickshell.processId
    // the palette's settings: palette.py's defaults
    readonly property string scheme: "scheme-tonal-spot"
    readonly property string mode: "dark"
    readonly property real contrast: 0
    property string lastError: ""

    // false when the path is not absolute or the setting is set in Nix
    function set(p) {
        if (p !== "" && !p.startsWith("/")) return false;
        return Settings.set("wallpaper.path", p);
    }

    function renderPalette() {
        if (!paletteFollows || path === "" || renderer.running || writer.running) return;
        if (Settings.stateValue("wallpaper.paletteFrom", "") === path) return;
        renderer.target = path;
        renderer.command = Files.matugenCommand(matugen, workDir, [{ name: "palette.json", input: themeDir + "/templates/palette.json" }],
                                                ["image", path], scheme, mode, contrast, ["--source-color-index", "0"]);
        renderer.running = true;
    }
    onPathChanged: Qt.callLater(renderPalette)
    onPaletteFollowsChanged: Qt.callLater(renderPalette)
    Component.onCompleted: Qt.callLater(renderPalette)

    function failed(message) {
        lastError = message;
        console.warn("rutile: no palette from the wallpaper: " + message);
        if (renderer.target !== path) renderPalette();       // it changed meanwhile
    }

    FileView {
        id: roles
        path: root.themeDir + "/roles.json"
        blockLoading: true
    }

    Process {
        id: renderer
        property string target: ""
        stdout: StdioCollector { id: rendered }
        stderr: StdioCollector { id: errors }
        onExited: code => {
            if (code !== 0) return root.failed(errors.text.trim() || ("matugen exited " + code));
            let doc;
            let roleNames;
            try {
                doc = JSON.parse(Files.parseRead(rendered.text)["palette.json"] ?? "");
                roleNames = JSON.parse(roles.text()).roles;
            } catch (e) {
                return root.failed("matugen produced no palette: " + e);
            }
            const errs = Palette.validate(doc, roleNames);
            if (errs.length) return root.failed("invalid palette: " + errs.join("; "));
            writer.target = target;
            writer.command = Files.applyCommand([
                { op: "write", path: root.palettePath, text: Palette.finish(doc, root.scheme, root.contrast) },
                { op: "remove", path: root.workDir + "/matugen.toml" }]);
            writer.running = true;
        }
    }
    Process {
        id: writer
        property string target: ""
        stderr: StdioCollector { id: writeErrors }
        onExited: code => {
            if (code !== 0) return root.failed(writeErrors.text.trim() || "could not write " + root.palettePath);
            root.lastError = "";
            Settings.setState("wallpaper.paletteFrom", target);
            if (target !== root.path) root.renderPalette();
        }
    }
}
