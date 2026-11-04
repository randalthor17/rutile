// The greeter's data (plan 6.2, D97): who can sign in, which sessions there are, what was chosen last time, as plain
// functions over the files' text, so they test offscreen.
.pragma library

// People who can sign in, from /etc/passwd's text: uid 1000 to 59999 (NixOS's normal users) with a login shell, as
// [{name, realName, uid}], by uid. realName is the GECOS field's first part, or the name.
function users(passwd) {
    var out = [];
    String(passwd || "").split("\n").forEach(function (line) {
        var f = line.split(":");
        if (f.length < 7) return;
        var uid = parseInt(f[2], 10);
        if (!(uid >= 1000 && uid < 60000)) return;
        if (/(nologin|\/false)$/.test(f[6]) || f[6] === "") return;
        var real = f[4].split(",")[0].trim();
        out.push({ name: f[0], realName: real || f[0], uid: uid });
    });
    return out.sort(function (a, b) { return a.uid - b.uid; });
}

// The marker before each session file's text in what sessionsCommand prints.
var MARK = "@@rutile-session:";

// The command that prints every wayland-sessions/*.desktop file in `dirs` (the data directories), each after a
// MARK line with its path.
function sessionsCommand(dirs) {
    return ["sh", "-c", 'for d in "$@"; do for f in "$d"/wayland-sessions/*.desktop; do [ -f "$f" ] && ' +
            'printf "\\n' + MARK + '%s\\n" "$f" && cat "$f"; done; done; exit 0', "sh"].concat(dirs);
}

// Sessions from that text, as [{id, name, command: [args], desktop (DesktopNames joined by colons, or the id)}]:
// the first of an id wins (the data directories' order), hidden ones and ones without Exec left out, by name.
function sessions(text) {
    var out = [], seen = {};
    String(text || "").split("\n" + MARK).forEach(function (chunk) {
        var nl = chunk.indexOf("\n");
        if (nl < 0) return;
        var path = chunk.substring(0, nl);
        var id = path.substring(path.lastIndexOf("/") + 1).replace(/\.desktop$/, "");
        if (id === "" || seen[id]) return;
        var entry = {}, inEntry = false;
        chunk.substring(nl + 1).split("\n").forEach(function (line) {
            if (/^\[.*\]$/.test(line.trim())) { inEntry = line.trim() === "[Desktop Entry]"; return; }
            var eq = line.indexOf("=");
            if (!inEntry || eq < 0) return;
            var key = line.substring(0, eq).trim();
            if (!(key in entry)) entry[key] = line.substring(eq + 1).trim();
        });
        if (!entry.Exec || entry.Hidden === "true" || entry.NoDisplay === "true") return;
        var command = execArgs(entry.Exec);
        if (command.length === 0) return;
        seen[id] = true;
        out.push({ id: id, name: entry.Name || id, command: command,
                   desktop: (entry.DesktopNames || id).split(";").filter(function (d) { return d !== ""; }).join(":") });
    });
    return out.sort(function (a, b) { return a.name.localeCompare(b.name); });
}

// A desktop entry's Exec as arguments: quotes and backslashes as the spec has them, field codes (%f, %U...) dropped.
function execArgs(exec) {
    var args = [], cur = "", has = false, quote = false;
    var s = String(exec || "");
    for (var i = 0; i < s.length; i++) {
        var c = s[i];
        if (quote) {
            if (c === "\\" && i + 1 < s.length) { cur += s[++i]; continue; }
            if (c === '"') { quote = false; continue; }
            cur += c;
        } else if (c === '"') { quote = true; has = true; }
        else if (c === " " || c === "\t") { if (has) args.push(cur); cur = ""; has = false; }
        else { cur += c; has = true; }
    }
    if (has) args.push(cur);
    return args.filter(function (a) { return !/^%[a-zA-Z]$/.test(a); })
               .map(function (a) { return a.replace(/%%/g, "%"); });
}

// What to show first: the last user if still there, else the first; that user's last session, else niri's, else the
// first. `state` is the saved {lastUser, sessions: {user: id}} (or anything else: nothing saved).
function initialUser(users, state) {
    var last = state && state.lastUser;
    for (var i = 0; i < users.length; i++) if (users[i].name === last) return last;
    return users.length ? users[0].name : "";
}
function initialSession(sessions, state, user) {
    var want = state && state.sessions && state.sessions[user];
    var ids = sessions.map(function (s) { return s.id; });
    if (ids.indexOf(want) >= 0) return want;
    if (ids.indexOf("niri") >= 0) return "niri";
    return ids.length ? ids[0] : "";
}
// The state to save after `user` signs in to `session`.
function remembered(state, user, session) {
    var sessions = Object.assign({}, (state && state.sessions) || {});
    sessions[user] = session;
    return { lastUser: user, sessions: sessions };
}
function parseState(text) {
    try {
        var s = JSON.parse(text);
        return s && typeof s === "object" ? s : {};
    } catch (e) {
        return {};
    }
}

// The environment the session gets on top of PAM's.
function sessionEnv(session) {
    return ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + session.id, "XDG_CURRENT_DESKTOP=" + session.desktop];
}

// How a greetd question shows: a password question as the field's "Password" alone; anything else as the message
// above the field, with its words (without a trailing colon) as the field's placeholder too.
function promptText(prompt, secret) {
    var p = String(prompt || "").trim();
    if (secret && (p === "" || /^password:?$/i.test(p))) return { placeholder: "Password", message: "" };
    var words = p.replace(/:\s*$/, "");
    return { placeholder: words !== "" ? words : (secret ? "Password" : "Answer"), message: p };
}

// What greetd is asked to run for a session. greetd joins the words with spaces and runs that with /bin/sh after
// reading /etc/profile (so the system's PATH is there for Exec=niri-session); a word with anything a shell would
// read differently goes in single quotes, so it stays one word.
function launchCommand(session) {
    return session.command.map(function (w) {
        return /^[A-Za-z0-9_\/.,:=@%+-]+$/.test(w) ? w : "'" + w.replace(/'/g, "'\\''") + "'";
    });
}

