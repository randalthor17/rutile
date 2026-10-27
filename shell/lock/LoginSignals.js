// systemd-logind's signals as `dbus-monitor --system` prints them, for the lock screen's triggers (plan 2.8): Lock on
// our session (`loginctl lock-session`, idle tools) and PrepareForSleep on the manager (suspend and resume). Kept
// apart so the parsing tests offscreen.
.pragma library

// logind's object path for a session id, escaped as sd-bus does: anything but [A-Za-z0-9] (and a digit in
// first place) becomes _ and two hex digits ("3" is "_33", "c2" is "c2").
function sessionPath(id) {
    var s = String(id || "");
    if (s === "") return "";
    var out = "";
    for (var i = 0; i < s.length; i++) {
        var c = s.charAt(i);
        if (/[A-Za-z0-9]/.test(c) && !(i === 0 && /[0-9]/.test(c))) out += c;
        else out += "_" + ("0" + s.charCodeAt(i).toString(16)).slice(-2);
    }
    return "/org/freedesktop/login1/session/" + out;
}

// The dbus-monitor match rules: our session's Lock, and the manager's PrepareForSleep.
function matchRules(path) {
    return ["type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Session',member='Lock',path='"
            + path + "'",
            "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"];
}

// Feeds one output line; `state` carries what spans lines (a PrepareForSleep's boolean comes on the next line).
// Returns "lock" (our session's Lock), "sleep" (about to suspend), "wake" (resumed) or "".
function feed(line, state, path) {
    var l = String(line);
    if (/^signal /.test(l)) {
        state.pending = "";
        if (/member=Lock$/.test(l) && /interface=org\.freedesktop\.login1\.Session;/.test(l)
                && l.indexOf("path=" + path + ";") >= 0)
            return "lock";
        if (/interface=org\.freedesktop\.login1\.Manager; member=PrepareForSleep$/.test(l))
            state.pending = "sleep";
        return "";
    }
    if (state.pending === "sleep") {
        state.pending = "";
        var m = l.match(/^\s*boolean (true|false)\s*$/);
        if (m) return m[1] === "true" ? "sleep" : "wake";
    }
    return "";
}
