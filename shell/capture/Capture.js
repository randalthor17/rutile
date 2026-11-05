// Screenshots and screen recording (D120) as plain functions: the commands, where files go, how the time reads.
// On niri its own screenshot actions are used (its region picker, a window, a screen; saved and copied as niri's
// config says); elsewhere grim and slurp. Recording is wf-recorder's (niri has none). Every path and choice reaches
// the scripts as arguments, never inside them.
.pragma library

var TARGETS = ["region", "window", "screen"];

function pad(n) {
    return (n < 10 ? "0" : "") + n;
}

// "2026-11-05 21-04-33", as niri names its screenshots.
function stamp(date) {
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + " " +
           pad(date.getHours()) + "-" + pad(date.getMinutes()) + "-" + pad(date.getSeconds());
}

// Where a screenshot (without niri) or a recording goes: XDG_PICTURES_DIR / XDG_VIDEOS_DIR when set, else ~/Pictures
// and ~/Videos; in Screenshots and Screencasts there, as niri and GNOME do.
function screenshotPath(env, date) {
    return (env.pictures || env.home + "/Pictures") + "/Screenshots/Screenshot from " + stamp(date) + ".png";
}
function recordingPath(env, date) {
    return (env.videos || env.home + "/Videos") + "/Screencasts/Screencast from " + stamp(date) + ".mp4";
}

// niri's action for a screenshot of `target`.
function niriCommand(target) {
    var action = { region: "screenshot", window: "screenshot-window", screen: "screenshot-screen" }[target];
    return action ? ["niri", "msg", "action", action] : null;
}

// grim's screenshot of a region (slurp picks it) or a screen (`output`), saved to `path` and copied. No window
// without niri: null.
function grimCommand(target, output, path) {
    if (target !== "region" && target !== "screen") return null;
    return ["sh", "-c",
            'mkdir -p "$(dirname "$1")" || exit 1\n' +
            'if [ "$2" = region ]; then g=$(slurp) || exit 1; grim -g "$g" "$1" || exit 1\n' +
            'else grim -o "$3" "$1" || exit 1; fi\n' +
            'wl-copy --type image/png < "$1"',
            "sh", path, target, output];
}

// wf-recorder recording a region (slurp picks it) or a screen (`output`) to `path`, with the microphone when
// `audio`. It runs in the foreground (exec), so stopping the process stops the recording and finishes the file.
function recordCommand(target, output, path, audio) {
    if (target !== "region" && target !== "screen") return null;
    return ["sh", "-c",
            'mkdir -p "$(dirname "$1")" || exit 1\n' +
            'a=""; [ "$4" = 1 ] && a="--audio"\n' +
            'if [ "$2" = region ]; then g=$(slurp) || exit 1; exec wf-recorder -y $a -g "$g" -f "$1"\n' +
            'else exec wf-recorder -y $a -o "$3" -f "$1"; fi',
            "sh", path, target, output, audio ? "1" : "0"];
}

// Seconds as m:ss (h:mm:ss from an hour), for the recording pill.
function elapsed(seconds) {
    var s = Math.max(0, Math.floor(seconds));
    var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
    return (h > 0 ? h + ":" + pad(m) : String(m)) + ":" + pad(s % 60);
}

// The file name alone, for a toast.
function fileName(path) {
    return String(path || "").replace(/^.*\//, "");
}
