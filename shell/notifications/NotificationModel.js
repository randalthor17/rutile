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
