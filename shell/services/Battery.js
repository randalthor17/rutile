// Low battery warnings (plan 2.13 B1, D136), as plain functions so they test offscreen: which warning is due as the
// charge falls, and what it says. PowerService.qml sends them as notifications.
.pragma library

// The warnings, most severe last: at 20% and 10% a notification, at 5% a critical one that stays until plugged in.
var LEVELS = [
    { key: "low", at: 20, critical: false },
    { key: "lower", at: 10, critical: false },
    { key: "critical", at: 5, critical: true }
];

// The warning due at `percent` (0 to 100) while discharging, given the keys already warned this discharge: the most
// severe level reached that was not warned, or null. A shell that starts at 8% warns once, for 10%.
function due(percent, discharging, warned) {
    if (!discharging) return null;
    var hit = null;
    for (var i = 0; i < LEVELS.length; i++)
        if (percent <= LEVELS[i].at) hit = LEVELS[i];
    return hit && warned.indexOf(hit.key) < 0 ? hit : null;
}

// The keys warned once `level` has been: it and every milder one, so a later, milder one never comes after it.
function warnedAfter(level) {
    var out = [];
    for (var i = 0; i < LEVELS.length; i++) {
        out.push(LEVELS[i].key);
        if (LEVELS[i].key === level.key) break;
    }
    return out;
}

// "1 h 25 min", "40 min", "" for unknown (seconds).
function duration(seconds) {
    if (!(seconds > 0)) return "";
    var m = Math.round(seconds / 60);
    if (m < 60) return m + " min";
    return Math.floor(m / 60) + " h" + (m % 60 ? " " + (m % 60) + " min" : "");
}

// What UPower does at the end (GetCriticalAction), in words.
function actionText(action) {
    return ({ PowerOff: "turn off", Hibernate: "hibernate", HybridSleep: "hibernate", Suspend: "sleep" })[action] || "";
}

// The notification for `level`: {summary, body, critical}.
function message(level, percent, secondsLeft, criticalAction) {
    var left = duration(secondsLeft);
    var charge = Math.round(percent) + "%" + (left ? ", about " + left + " left" : " left");
    if (!level.critical)
        return { summary: "Battery low", body: charge + ". Plug in soon, or turn on Power saver.", critical: false };
    var end = actionText(criticalAction);
    return { summary: "Battery critically low",
             body: charge + ". Plug in now" + (end ? ": the computer will " + end + " soon." : "."), critical: true };
}

// The notification sent over D-Bus to whichever server runs (the shell's own, normally): busctl's arguments, every
// text as one argument as it is. `replaces` is the id of the warning shown, so a newer one takes its place.
function notifyCommand(msg, replaces) {
    return ["busctl", "--user", "--", "call", "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
            "Battery", String(replaces || 0), msg.critical ? "battery_alert" : "battery_2_bar", msg.summary, msg.body,
            "0", "2", "urgency", "y", msg.critical ? "2" : "1", "category", "s", "device", msg.critical ? "0" : "-1"];
}

function closeCommand(id) {
    return ["busctl", "--user", "call", "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications", "CloseNotification", "u", String(id)];
}

// busctl's answer to Notify, "u 7": the id, or 0.
function parseId(text) {
    var m = /^u (\d+)/.exec(String(text).trim());
    return m ? parseInt(m[1], 10) : 0;
}
