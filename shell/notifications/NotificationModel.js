// Notifications as plain data (plan 2.8), so the cards and the rules test offscreen. NotificationService.qml turns
// Quickshell's Notification objects into {id, appName, appIcon, image, summary, body, urgency, actions: [{id,
// text}], time, critical}; the cards show those.
.pragma library

var urgencyCritical = 2;                // NotificationUrgency.Critical
var defaultTimeout = 6000;              // ms a popup stays when the sender leaves it to us
var maxPopups = 3;                      // more wait in the list; the newest show

// The text without markup: tags dropped (a <br> or </p> is a line break), the common entities decoded. Senders
// send markup even when the server does not ask for it, and showing it as rich text would load images from it.
function plain(text) {
    if (!text) return "";
    return String(text)
        .replace(/<br\s*\/?>/gi, "\n").replace(/<\/p>/gi, "\n")
        .replace(/<[^>]*>/g, "")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'")
        .replace(/&amp;/g, "&")
        .trim();
}

// How long a popup stays, in ms; 0 means until it is dismissed. A critical notification stays, and so does one
// whose sender asks for 0; -1 (the sender does not mind) is our default. Quickshell gives the sender's timeout
// in ms, though its documentation says seconds (seen in a probe with Quickshell 0.3.2).
function timeout(expireTimeout, urgency) {
    if (urgency === urgencyCritical) return 0;
    if (expireTimeout === 0) return 0;
    if (!(expireTimeout > 0)) return defaultTimeout;
    return expireTimeout;
}

// When it came, for the card: "now" under a minute, "5 min", "2 h", then the clock time of that day, or the date
// for an older one. `timeText(date)` and `dateText(date)` format a Date in the user's locale.
function ago(time, now, timeText, dateText) {
    var s = Math.floor((now - time) / 1000);
    if (s < 60) return "now";
    if (s < 3600) return Math.floor(s / 60) + " min";
    var then = new Date(time);
    if (new Date(now).toDateString() === then.toDateString()) return s < 6 * 3600 ? Math.floor(s / 3600) + " h" : timeText(then);
    return dateText(then);
}

// The popups to show from those waiting (oldest first): at most maxPopups, the newest.
function visiblePopups(ids) {
    return ids.length > maxPopups ? ids.slice(ids.length - maxPopups) : ids.slice();
}

// Whether a new notification pops up: not while Do not disturb is on, unless it is critical.
function pops(urgency, dnd) {
    return !dnd || urgency === urgencyCritical;
}

// The sound files to try for a notification that pops up, in order (the player plays the first that exists); []
// for none. The sender's hints (the Desktop Notifications spec) come first: suppress-sound, then sound-file (an
// absolute path or a file:// URL), then sound-name from the freedesktop sound theme; otherwise the theme's
// message-new-instant. `dataDirs` are where sound themes live ($XDG_DATA_HOME, then $XDG_DATA_DIRS).
var defaultSound = "message-new-instant";
var soundExtensions = [".oga", ".ogg", ".wav"];
function soundFiles(hints, dataDirs) {
    hints = hints || {};
    if (hints["suppress-sound"] === true) return [];
    var file = String(hints["sound-file"] || "");
    if (file.indexOf("file://") === 0) file = decodeURIComponent(file.slice(7));
    if (file.charAt(0) === "/") return [file];
    var name = String(hints["sound-name"] || "");
    // a name is one path segment, never a way out of the theme
    if (!/^[A-Za-z0-9._-]+$/.test(name) || name.charAt(0) === ".") name = defaultSound;
    var names = name === defaultSound ? [name] : [name, defaultSound];
    var out = [];
    for (var n = 0; n < names.length; n++)
        for (var d = 0; d < dataDirs.length; d++)
            for (var e = 0; e < soundExtensions.length; e++)
                out.push(dataDirs[d].replace(/\/+$/, "") + "/sounds/freedesktop/stereo/" + names[n] + soundExtensions[e]);
    return out;
}

// The player's command: pw-play (PipeWire) on the first of `files` that exists, with the Notification media role
// so the session's policy can treat it as one. The files are arguments, never part of the script.
function playCommand(files) {
    return ["sh", "-c", 'for f; do [ -f "$f" ] && exec pw-play --media-role=Notification "$f"; done', "sh"]
        .concat(files);
}

// $XDG_DATA_HOME (or ~/.local/share) and then $XDG_DATA_DIRS (or /usr/local/share:/usr/share), as the base
// directory spec says; empty entries dropped.
function dataDirs(dataHome, dataDirsVar, home) {
    var first = dataHome || (home ? home + "/.local/share" : "");
    var rest = (dataDirsVar || "/usr/local/share:/usr/share").split(":");
    return [first].concat(rest).filter(function (d) { return d.charAt(0) === "/"; });
}

// The list's rows, grouped by app (D47): each app in the order of its newest notification; its newest card, then
// the rest when the app is in `expanded` ({appName: true}), and one "more" row while it has more than one:
// [{key, kind: "card", id} | {key, kind: "more", app, count, expanded}]. `list` is newest first.
function groupRows(list, expanded) {
    var order = [], byApp = Object.create(null);    // no prototype: an app may be called "constructor"
    for (var i = 0; i < list.length; i++) {
        var app = list[i].appName || "";
        if (!byApp[app]) {
            byApp[app] = [];
            order.push(app);
        }
        byApp[app].push(list[i]);
    }
    var rows = [];
    for (var g = 0; g < order.length; g++) {
        var items = byApp[order[g]];
        var open = !!expanded && expanded[order[g]] === true;    // not `in`: {} has a "constructor" too
        var shown = open ? items : items.slice(0, 1);
        for (var k = 0; k < shown.length; k++) rows.push({ key: "n" + shown[k].id, kind: "card", id: shown[k].id });
        if (items.length > 1)
            rows.push({ key: "more:" + order[g], kind: "more", app: order[g], count: items.length - 1, expanded: open });
    }
    return rows;
}
