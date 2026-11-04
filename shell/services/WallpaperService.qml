pragma Singleton
// The wallpaper (plan 2.9): the wallpaper.path setting, which WallpaperWindow shows on every screen and the lock
// screen blurs. The palette is rendered into the file PaletteWatcher reads, so the colors follow: from the wallpaper
// (its dominant color) while wallpaper.palette is on and there is one, else from the style.seed color, with the
// style's scheme, mode and contrast (D65); again whenever one of those changes. matugen, checked as
// tools/palette.py checks it (Palette.js), then written atomically; a failed or invalid render leaves the palette
// as it was. No Python (D53). What was rendered last is remembered in state.json, so a restart does not render
// again.
import QtQuick
import Quickshell
import Quickshell.Io
import "Files.js" as Files
import "Palette.js" as Palette

Singleton {
    id: root

    // the wallpaper.path setting, or Rutile's own when it is unset (D98)
    readonly property string defaultPath: Quickshell.shellDir + "/../theme/wallpapers/rutile-default.jpg"
    readonly property string path: (Settings.value("wallpaper.path") ?? "") || defaultPath
    readonly property bool paletteFollows: Settings.value("wallpaper.palette") === true
    readonly property string palettePath: Quickshell.env("RUTILE_PALETTE")
        || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/rutile/palette.json")
    readonly property string themeDir: Quickshell.shellDir + "/../theme"
    // RUTILE_MATUGEN: tests only (a stand-in that logs and writes a fixture instead of running matugen)
    readonly property string matugen: Quickshell.env("RUTILE_MATUGEN") || "matugen"
    readonly property string workDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rutile-palette-" + Quickshell.processId
    // the palette's settings (D65)
    // (Settings.value gives the schema's default when unset)
    readonly property string scheme: Settings.value("style.scheme")
    readonly property string mode: Settings.value("style.mode")
    readonly property real contrast: Settings.value("style.contrast")
    readonly property string seed: Settings.value("style.seed")
    // the image the palette comes from, or "" for the seed color; Rutile's own wallpaper is drawn in the seed's
    // blue, so with it the palette stays the seed's (D98)
    readonly property string source: paletteFollows && (Settings.value("wallpaper.path") ?? "") !== "" ? path : ""
    // what a render makes: a new one when this changes
    readonly property string wanted: JSON.stringify([source || seed, scheme, mode, contrast])
    property string lastError: ""

    // what the sign-in screen shows for this person (D98): RUTILE_GREETER_USER_DIR replaces it in the tests
    readonly property string greeterDir: Quickshell.env("RUTILE_GREETER_USER_DIR")
        || ("/var/lib/rutile-greeter/users/" + (Quickshell.env("USER") || "nobody"))
    property bool shareAgain: false
    function shareWithGreeter() {
        if (sharer.running) shareAgain = true;
        else sharer.running = true;
    }
    onPathChanged: Qt.callLater(shareWithGreeter)
    Process {
        id: sharer
        command: Files.greeterShareCommand(root.greeterDir, root.path, root.palettePath)
        onExited: {
            if (!root.shareAgain) return;
            root.shareAgain = false;
            running = true;
        }
    }

    // false when the path is not absolute or the setting is set in Nix
    function set(p) {
        if (p !== "" && !p.startsWith("/")) return false;
        return Settings.set("wallpaper.path", p);
    }

    function renderPalette() {
        if (renderer.running || writer.running) return;
        if (Settings.stateValue("wallpaper.paletteKey", "") === wanted) return;
        renderer.target = wanted;
        renderer.from = source || seed;
        renderer.command = Files.matugenCommand(matugen, workDir, [{ name: "palette.json", input: themeDir + "/templates/palette.json" }],
                                                source ? ["image", source] : ["color", "hex", seed], scheme, mode, contrast,
                                                source ? ["--source-color-index", "0"] : []);
        renderer.running = true;
    }
    onWantedChanged: Qt.callLater(renderPalette)
    Component.onCompleted: {
        Qt.callLater(renderPalette);
        Qt.callLater(shareWithGreeter);
    }

    function failed(message) {
        lastError = message;
        console.warn("rutile: no palette: " + message);
        if (renderer.target !== wanted) renderPalette();       // it changed meanwhile
    }

    FileView {
        id: roles
        path: root.themeDir + "/roles.json"
        blockLoading: true
    }

    Process {
        id: renderer
        property string target: ""              // the `wanted` it renders
        property string from: ""                // its image, or its color
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
            writer.from = from;
            writer.command = Files.applyCommand([
                { op: "write", path: root.palettePath, text: Palette.finish(doc, JSON.parse(target)[1], JSON.parse(target)[3]) },
                { op: "remove", path: root.workDir + "/matugen.toml" }]);
            writer.running = true;
        }
    }
    Process {
        id: writer
        property string target: ""
        property string from: ""
        stderr: StdioCollector { id: writeErrors }
        onExited: code => {
            if (code !== 0) return root.failed(writeErrors.text.trim() || "could not write " + root.palettePath);
            root.lastError = "";
            Settings.setState("wallpaper.paletteFrom", from);
            Settings.setState("wallpaper.paletteKey", target);
            root.shareWithGreeter();
            if (target !== root.wanted) root.renderPalette();
        }
    }
}
