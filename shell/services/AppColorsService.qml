pragma Singleton
// Other apps in the shell's colors (D52, preliminary): while `appColors.enabled` is on, the apps switched on under
// it wear the palette, again whenever the palette changes (a new wallpaper); an app switched off, or the main
// switch, takes its colors back out. Everything is off by default, and with nothing on and nothing themed before
// (state.json's appColors.done) nothing runs at all. No Python (D53): one run is matugen with the switched-on
// apps' templates (from the palette's source color, scheme, mode and contrast, so exactly the shell's colors),
// then one read of the files involved, the plan (AppTheme.js), and one `sh` that applies it (Files.js).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "AppTheme.js" as AppTheme
import "Files.js" as Files

Singleton {
    id: root

    readonly property var apps: AppTheme.ORDER
    readonly property bool enabled: Settings.value("appColors.enabled") === true
    readonly property var wanted: enabled ? apps.filter(a => Settings.value("appColors." + a) === true) : []
    readonly property var done: Settings.stateValue("appColors.done", {})
    readonly property var synced: apps.filter(a => a in done)
    readonly property string palettePath: WallpaperService.palettePath
    readonly property string home: Quickshell.env("HOME")
    readonly property var dirs: ({
        config: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config",
        cache: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache",
        data: Quickshell.env("XDG_DATA_HOME") || home + "/.local/share",
        home: home,
        theme: Quickshell.shellDir + "/../theme/apps",
        // the compiled Firefox host (D54): `make native` builds it; RUTILE_PYWALFOX_HOST: elsewhere (a package, tests)
        host: Quickshell.env("RUTILE_PYWALFOX_HOST") || Quickshell.shellDir + "/../build/rutile-pywalfox-host"
    })
    readonly property string workDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rutile-appcolors-" + Quickshell.processId
    property string lastError: ""
    property int runs: 0
    property bool again: false

    function schedule() {
        if (wanted.length === 0 && synced.length === 0) return;   // nothing on, nothing to take back
        debounce.restart();
    }
    // One run: render (when an app is on), read, plan, apply.
    function sync() {
        if (job.running) {
            again = true;
            return;
        }
        job.target = wanted.slice();
        job.rendered = {};
        if (job.target.length === 0) return read();
        // The palette's settings; without a palette file (no wallpaper yet), the shell's own colors: the same
        // source color, on the palette's defaults.
        let doc;
        try {
            doc = JSON.parse(palette.text());
        } catch (e) {
            doc = { source_color: Colors.sourceColor };
        }
        job.stage = "render";
        job.command = Files.matugenCommand(WallpaperService.matugen, workDir, AppTheme.templates(dirs, job.target),
                                           ["color", "hex", doc.source_color], doc.scheme ?? "scheme-tonal-spot",
                                           doc.mode ?? WallpaperService.mode, doc.contrast ?? 0);
        job.mode = doc.mode ?? WallpaperService.mode;
        job.running = true;
    }
    function read() {
        job.stage = "read";
        job.command = Files.readCommand(AppTheme.paths(dirs, job.target.concat(synced)));
        job.running = true;
    }
    function apply(files) {
        // the rendered files are copied from matugen's output folder (an argument is capped at 128 KiB)
        const sources = {};
        for (const name in job.rendered) sources[name] = workDir + "/out/" + name;
        const p = AppTheme.plan({ dirs: dirs, wanted: job.target, done: done, files: files, rendered: job.rendered,
                                  sources: sources, mode: job.mode });
        job.done = p.done;
        job.warning = p.errors.join("; ");
        if (p.ops.length === 0) return finish(true, "");
        job.stage = "apply";
        try {
            job.command = Files.applyCommand(p.ops);
        } catch (e) {
            return finish(false, String(e.message || e));
        }
        job.running = true;
    }
    function finish(ok, error) {
        runs++;
        lastError = error || (ok ? job.warning : "");
        if (ok && job.warning) console.warn("rutile: other apps' colors: " + job.warning);
        if (ok) Settings.setState("appColors.done", job.done);
        else console.warn("rutile: other apps' colors: " + error);
        if (again || JSON.stringify(job.target) !== JSON.stringify(wanted)) {
            again = false;
            schedule();
        }
    }

    onWantedChanged: schedule()
    Component.onCompleted: schedule()

    // Several switches flipped together, or a palette written in steps, make one run.
    Timer {
        id: debounce
        interval: 400
        onTriggered: root.sync()
    }

    // The palette changes with the wallpaper: the apps follow. The shell's colors are the signal (PaletteWatcher
    // notices a palette written after start, which this FileView, watching only a file that exists, would not).
    Connections {
        target: Colors
        function onSourceColorChanged() {
            palette.reload();
            root.schedule();
        }
    }
    // and each palette the shell renders (a mode, scheme or contrast change keeps the source color, D65)
    readonly property string paletteKey: Settings.stateValue("wallpaper.paletteKey", "")
    onPaletteKeyChanged: {
        palette.reload();
        schedule();
    }
    FileView {
        id: palette
        path: root.palettePath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: { reload(); root.schedule(); }
    }

    Process {
        id: job
        property string stage: ""
        property var target: []
        property var rendered: ({})
        property var done: ({})
        property string warning: ""
        property string mode: "dark"
        // The result once the process has exited and both its outputs are read: at `exited` the text may not have
        // arrived yet (an error's message was lost that way: "could not change the apps' files").
        property int exitCode: -1
        property bool outRead: false
        property bool errRead: false
        onRunningChanged: if (running) {
            exitCode = -1;
            outRead = false;
            errRead = false;
        }
        stdout: StdioCollector {
            id: out
            onStreamFinished: { job.outRead = true; job.settle(); }
        }
        stderr: StdioCollector {
            id: errors
            onStreamFinished: { job.errRead = true; job.settle(); }
        }
        onExited: code => {
            exitCode = code;
            settle();
        }
        function settle() {
            if (exitCode < 0 || !outRead || !errRead) return;
            const code = exitCode;
            exitCode = -1;
            handle(code);
        }
        function handle(code) {
            if (stage === "render") {
                if (code !== 0) return root.finish(false, errors.text.trim() || "matugen exited " + code);
                rendered = Files.parseRead(out.text);
                return root.read();
            }
            if (stage === "read") {
                if (code !== 0) return root.finish(false, errors.text.trim() || "could not read the apps' files");
                return root.apply(Files.parseRead(out.text));
            }
            // a step that may fail without failing the run (GTK's mode without dconf) says so here
            if (code === 0 && errors.text.trim()) console.warn("rutile: other apps' colors: " + errors.text.trim());
            root.finish(code === 0, code === 0 ? "" : (errors.text.trim() || "could not change the apps' files"));
        }
    }
}
