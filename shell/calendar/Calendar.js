// The calendar's data (the clock's calendar popup, D93; the widgets' calendar source, D79): events read from iCalendar
// text (RFC 5545) and their times in a range, repeating ones included, and the days of a month as the popup draws
// them. Plain functions, so they test offscreen with fixed dates.
//
// Repeating events: RRULE with FREQ DAILY, WEEKLY, MONTHLY or YEARLY, INTERVAL, COUNT, UNTIL, BYDAY (weekly: the
// days of the week; monthly: "2MO", "-1FR" or plain days) and BYMONTHDAY (monthly); EXDATE leaves times out, and an
// event with a RECURRENCE-ID replaces its series' time. A rule with anything else (BYSETPOS, BYWEEKNO, HOURLY...)
// shows its first time only. Times repeat in local time, as the clock on the wall does across a DST change; a TZID
// time is taken as local.
.pragma library

var DAY = 86400000;

function unfold(text) {
    return String(text || "").replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "");
}
function unescapeText(v) {
    return v.replace(/\\n/gi, " ").replace(/\\([,;\\])/g, "$1");
}
// "20261105T100000Z", "20261105T100000" (local, or in a TZID taken as local) or a date; {date, allDay} or null
function icsDate(value, params) {
    var m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(value || "");
    if (!m) return null;
    if (!m[4]) return { date: new Date(+m[1], +m[2] - 1, +m[3]), allDay: true };
    if (m[7]) return { date: new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])), allDay: false };
    return { date: new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]), allDay: /VALUE=DATE(;|$)/.test(params || "") };
}
// "PT1H30M", "P1D", "-PT15M" in milliseconds; 0 for anything else
function icsDuration(value) {
    var m = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(value || "");
    if (!m) return 0;
    var ms = (((+(m[2] || 0) * 7 + +(m[3] || 0)) * 24 + +(m[4] || 0)) * 60 + +(m[5] || 0)) * 60000 + +(m[6] || 0) * 1000;
    return m[1] === "-" ? -ms : ms;
}

var WEEKDAYS = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };
// RRULE's value as {freq, interval, count, until, byDay: [{n, day}], byMonthDay: [], supported}, or null
function rule(value) {
    if (!value) return null;
    var r = { freq: "", interval: 1, count: 0, until: null, byDay: [], byMonthDay: [], supported: true };
    value.split(";").forEach(function (part) {
        var eq = part.indexOf("=");
        var key = part.substring(0, eq).toUpperCase(), v = part.substring(eq + 1);
        if (key === "FREQ") r.freq = v.toUpperCase();
        else if (key === "INTERVAL") r.interval = Math.max(1, parseInt(v, 10) || 1);
        else if (key === "COUNT") r.count = Math.max(0, parseInt(v, 10) || 0);
        else if (key === "UNTIL") r.until = icsDate(v, "");
        else if (key === "BYDAY") r.byDay = v.split(",").map(function (d) {
            var m = /^([+-]?\d+)?(SU|MO|TU|WE|TH|FR|SA)$/i.exec(d.trim());
            if (!m) r.supported = false;
            return m ? { n: m[1] ? parseInt(m[1], 10) : 0, day: WEEKDAYS[m[2].toUpperCase()] } : null;
        }).filter(function (d) { return d !== null; });
        else if (key === "BYMONTHDAY") r.byMonthDay = v.split(",").map(function (d) { return parseInt(d, 10); })
            .filter(function (d) { return d !== 0 && !isNaN(d); });
        else if (key !== "WKST" && key !== "") r.supported = false;
    });
    if (["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].indexOf(r.freq) < 0) r.supported = false;
    if (r.freq !== "WEEKLY" && r.freq !== "MONTHLY" && r.byDay.length > 0) r.supported = false;
    if (r.freq !== "MONTHLY" && r.byMonthDay.length > 0) r.supported = false;
    if (r.freq === "WEEKLY" && r.byDay.some(function (d) { return d.n !== 0; })) r.supported = false;
    return r;
}

// The VEVENTs as [{title, start: Date, end: Date, allDay, rule (or null), exdates: [ms], uid, recurrenceId (ms or
// null)}]. `end` is DTEND, or DTSTART plus DURATION, or for an event with neither its start (a day for an all-day one).
function icsEvents(text) {
    var out = [];
    var cur = null;
    unfold(text).split("\n").forEach(function (line) {
        if (line === "BEGIN:VEVENT") { cur = { exdates: [] }; return; }
        if (line === "END:VEVENT") {
            if (cur && cur.start) {
                var start = cur.start.date, allDay = cur.start.allDay;
                var end = cur.end ? cur.end.date : cur.duration ? new Date(start.getTime() + cur.duration)
                        : new Date(start.getTime() + (allDay ? DAY : 0));
                if (end < start) end = start;
                out.push({ title: cur.title || "Event", start: start, end: end, allDay: allDay, rule: rule(cur.rrule),
                           exdates: cur.exdates, uid: cur.uid || "", recurrenceId: cur.recurrenceId ?? null });
            }
            cur = null;
            return;
        }
        if (!cur) return;
        var colon = line.indexOf(":");
        if (colon < 0) return;
        var head = line.substring(0, colon), value = line.substring(colon + 1);
        var name = head.split(";")[0].toUpperCase();
        if (name === "SUMMARY") cur.title = unescapeText(value);
        else if (name === "DTSTART") cur.start = icsDate(value, head);
        else if (name === "DTEND") cur.end = icsDate(value, head);
        else if (name === "DURATION") cur.duration = icsDuration(value);
        else if (name === "RRULE") cur.rrule = value;
        else if (name === "UID") cur.uid = value;
        else if (name === "RECURRENCE-ID") {
            var r = icsDate(value, head);
            if (r) cur.recurrenceId = r.date.getTime();
        } else if (name === "EXDATE") value.split(",").forEach(function (v) {
            var d = icsDate(v, head);
            if (d) cur.exdates.push(d.date.getTime());
        });
    });
    return out;
}

// the start's time of day on day `y-m-d` (a date that runs over, Feb 30, is null)
function at(start, y, m, d) {
    var t = new Date(y, m, d, start.getHours(), start.getMinutes(), start.getSeconds());
    return t.getDate() === d && t.getMonth() === ((m % 12) + 12) % 12 ? t : null;
}
// The start times a rule makes, in order, while `more(time)`. Without a COUNT it skips the periods that end before
// `from`; a cap ends a rule that has gone wrong.
function ruleTimes(e, from, more) {
    var r = e.rule, s = e.start, out = [];
    var y = s.getFullYear(), mo = s.getMonth(), d = s.getDate();
    var made = 0;
    var skip = 0;
    if (!r.count && from > s) {
        var periods = r.freq === "DAILY" ? (from - s) / DAY : r.freq === "WEEKLY" ? (from - s) / (7 * DAY)
                    : r.freq === "MONTHLY" ? (from.getFullYear() - y) * 12 + from.getMonth() - mo : from.getFullYear() - y;
        skip = Math.max(0, Math.floor(periods / r.interval) - 1);
    }
    var until = r.until ? (r.until.allDay ? new Date(r.until.date.getTime() + DAY - 1) : r.until.date) : null;
    // one period's candidate times, sorted; true while going on
    function take(list) {
        list.sort(function (a, b) { return a - b; });
        for (var i = 0; i < list.length; i++) {
            var t = list[i];
            if (t < s) continue;
            if ((until && t > until) || (r.count && made >= r.count) || !more(t)) return false;
            made++;
            out.push(t);
        }
        return true;
    }
    for (var k = skip; k < skip + 5000; k++) {
        var list = [];
        if (r.freq === "DAILY") {
            list.push(new Date(y, mo, d + k * r.interval, s.getHours(), s.getMinutes(), s.getSeconds()));
        } else if (r.freq === "WEEKLY") {
            var weekStart = d - s.getDay() + 7 * k * r.interval;
            var days = r.byDay.length ? r.byDay.map(function (b) { return b.day; }) : [s.getDay()];
            days.forEach(function (wd) { list.push(new Date(y, mo, weekStart + wd, s.getHours(), s.getMinutes(), s.getSeconds())); });
        } else if (r.freq === "MONTHLY") {
            var first = new Date(y, mo + k * r.interval, 1);
            var fy = first.getFullYear(), fm = first.getMonth();
            var length = new Date(fy, fm + 1, 0).getDate();
            if (r.byDay.length) r.byDay.forEach(function (b) {
                var matches = [];
                for (var day = 1; day <= length; day++) if (new Date(fy, fm, day).getDay() === b.day) matches.push(day);
                var pick = b.n === 0 ? matches : [b.n > 0 ? matches[b.n - 1] : matches[matches.length + b.n]];
                pick.forEach(function (day) { if (day) list.push(at(s, fy, fm, day)); });
            });
            else (r.byMonthDay.length ? r.byMonthDay : [d]).forEach(function (md) {
                var day = md > 0 ? md : length + md + 1;
                if (day >= 1 && day <= length) list.push(at(s, fy, fm, day));
            });
        } else {
            list.push(at(s, y + k * r.interval, mo, d));
        }
        if (!take(list.filter(function (t) { return t !== null; }))) break;
    }
    return out;
}

// Every time of `events` that is on between `from` and `to` (Dates), soonest first, as [{title, start, end,
// allDay}]: a repeating event once per time, without its EXDATEs and the times another event replaces.
function occurrences(events, from, to) {
    var out = [];
    var replaced = {};
    (events || []).forEach(function (e) {
        if (e.recurrenceId !== null && e.uid) replaced[e.uid + "@" + e.recurrenceId] = true;
    });
    function on(start, end) {
        return start < to && (end > from || start >= from);
    }
    (events || []).forEach(function (e) {
        var length = e.end - e.start;
        if (!e.rule || !e.rule.supported || e.recurrenceId !== null) {
            if (on(e.start, e.end)) out.push({ title: e.title, start: e.start, end: e.end, allDay: e.allDay });
            return;
        }
        ruleTimes(e, from, function (t) { return t < to; }).forEach(function (t) {
            var end = new Date(t.getTime() + length);
            if (e.exdates.indexOf(t.getTime()) >= 0 || replaced[e.uid + "@" + t.getTime()] || !on(t, end)) return;
            out.push({ title: e.title, start: t, end: end, allDay: e.allDay });
        });
    });
    return out.sort(function (a, b) { return (a.start - b.start) || ((b.allDay ? 1 : 0) - (a.allDay ? 1 : 0)); });
}

// ---- reading ----
// "~/x" in `home`; any other path as it is
function expandHome(path, home) {
    return path.startsWith("~/") ? home + path.substring(1) : path;
}
// The command that prints a calendar's text: an .ics file's, or every .ics file's in a folder and the folders right
// in it (vdirsyncer keeps one folder per calendar and one file per event; sh's globs, no find). It fails (3) when the
// path is neither.
function readCommand(path) {
    return ["sh", "-c", 'if [ -f "$1" ]; then cat "$1"; elif [ -d "$1" ]; then ' +
            'for f in "$1"/*.ics "$1"/*/*.ics; do [ -f "$f" ] && cat "$f"; done; exit 0; else exit 3; fi', "sh", path];
}

// ---- calendar addresses (D94): Google's "secret address in iCal format", Outlook's, iCloud's... ----
// webcal:// is https:// for fetching; an address that is neither http(s) nor webcal is "".
function feedUrl(address) {
    var a = String(address || "").trim();
    if (/^webcal:\/\//i.test(a)) return "https://" + a.substring(9);
    return /^https?:\/\//i.test(a) ? a : "";
}
// What an address answered is a calendar (a sign-in page or an error is not).
function isCalendar(text) {
    return /^\s*BEGIN:VCALENDAR/i.test(String(text || ""));
}
// The cache file's name for an address: a hash, so the secret address itself is in no file name.
function cacheName(address) {
    var h1 = 0x811c9dc5, h2 = 0x01000193;
    var s = String(address || "");
    for (var i = 0; i < s.length; i++) {
        h1 = Math.imul(h1 ^ s.charCodeAt(i), 0x01000193) >>> 0;
        h2 = Math.imul(h2 ^ s.charCodeAt(i), 0x5bd1e995) >>> 0;
    }
    return ("0000000" + h1.toString(16)).slice(-8) + ("0000000" + h2.toString(16)).slice(-8);
}

// ---- the popup ----
function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
function dayKey(d) {
    return d.getFullYear() + "-" + (d.getMonth() < 9 ? "0" : "") + (d.getMonth() + 1) + "-" + (d.getDate() < 10 ? "0" : "") + d.getDate();
}
// "2026-11-04" as a Date, or null
function parseDay(text) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text || "");
    if (!m) return null;
    var d = new Date(+m[1], +m[2] - 1, +m[3]);
    return d.getMonth() === +m[2] - 1 ? d : null;
}

// The 42 days (six weeks) the month of `month` (a Date in it) shows, from the week its first day is in, as Dates.
// `firstDay` is the locale's first day of the week, 0 (Sunday) to 6; Qt's Locale.firstDayOfWeek gives Sunday as 0
// too.
function monthDays(month, firstDay) {
    var first = new Date(month.getFullYear(), month.getMonth(), 1);
    var back = (first.getDay() - (firstDay % 7) + 7) % 7;
    var out = [];
    for (var i = 0; i < 42; i++) out.push(new Date(first.getFullYear(), first.getMonth(), 1 - back + i));
    return out;
}

// The days of `days` (Dates) that have an event, as {dayKey: true}.
function busyDays(events, days) {
    var out = {};
    if (!days.length) return out;
    var from = startOfDay(days[0]), to = new Date(days[days.length - 1].getFullYear(), days[days.length - 1].getMonth(),
                                                  days[days.length - 1].getDate() + 1);
    occurrences(events, from, to).forEach(function (o) {
        // each day it is on (an all-day event's end is the next day's start, so it stops before)
        var last = o.end > o.start ? new Date(o.end.getTime() - 1) : o.start;
        for (var d = startOfDay(o.start); d <= last && d < to; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1))
            if (d >= from) out[dayKey(d)] = true;
    });
    return out;
}

// One day's events as the popup lists them: [{title, time}], all-day ones first. `time` is "All day", "9:00 – 10:00",
// or "9:00" for an event without an end; an event that began on an earlier day or ends on a later one shows its date.
function dayEvents(events, day, use24h, locale, timeText) {
    var from = startOfDay(day), to = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
    return occurrences(events, from, to).map(function (o) {
        function when(t) {
            return sameDay(t, day) ? timeText(t, use24h) : locale.toString(t, "MMM d") + ", " + timeText(t, use24h);
        }
        var time = o.allDay ? "All day"
                 : o.end > o.start ? when(o.start) + " – " + when(o.end) : when(o.start);
        return { title: o.title, time: time };
    });
}
