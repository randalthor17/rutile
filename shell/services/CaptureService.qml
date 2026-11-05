// Screenshots and screen recording (D120). screenshot() uses niri's own actions when niri runs (it announces each
// one on its event stream: NiriService.screenshotCaptured), else grim and slurp; record() runs wf-recorder until
// stop(). `done` reports what was saved, for a toast. Capture.js builds the commands.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../capture/Capture.js" as Capture

Singleton {
    id: root

    readonly property bool niri: NiriService.socketPath !== ""
    readonly property var dirs: ({ home: Quickshell.env("HOME") ?? "", pictures: Quickshell.env("XDG_PICTURES_DIR") ?? "",
                                   videos: Quickshell.env("XDG_VIDEOS_DIR") ?? "" })
    property bool recording: false
    property real recordingSince: 0          // ms, while recording
    property string recordingPath: ""

    signal done(string kind, string path, bool ok)   // kind: "screenshot" | "recording"

    // A screenshot of "region", "window" or "screen" (`output`: the screen's name, without niri). False when it
    // cannot be taken here (a window without niri) or one is being taken.
    function screenshot(target, output) {
        if (shot.running) return false;
        if (niri) {
            const c = Capture.niriCommand(target);
            if (!c) return false;
            Quickshell.execDetached(c);
            return true;
        }
        const path = Capture.screenshotPath(dirs, new Date());
        const c = Capture.grimCommand(target, output, path);
        if (!c) return false;
        shot.path = path;
        shot.command = c;
        shot.running = true;
        return true;
    }
    // Records "region" or "screen" until stop(); with the microphone when `audio`.
    function record(target, output, audio) {
        if (recording) return false;
        const path = Capture.recordingPath(dirs, new Date());
        const c = Capture.recordCommand(target, output, path, audio);
        if (!c) return false;
        recordingPath = path;
        recorder.command = c;
        recorder.running = true;
        recording = true;
        recordingSince = Date.now();
        return true;
    }
    function stop() {
        if (!recording) return false;
        recorder.signal(2);         // SIGINT: wf-recorder finishes the file
        return true;
    }

    Process {
        id: shot
        property string path: ""
        onExited: code => root.done("screenshot", path, code === 0)
    }
    Process {
        id: recorder
        onExited: code => {
            root.recording = false;
            // a region not picked (slurp cancelled) ends at once with no file
            root.done("recording", root.recordingPath, code === 0 && Date.now() - root.recordingSince > 500);
        }
    }
    Connections {
        target: NiriService
        function onScreenshotCaptured(path) { root.done("screenshot", path, true); }
    }
}
