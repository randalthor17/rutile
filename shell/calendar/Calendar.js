// The calendar's data (the clock's calendar popup, D93; the widgets' calendar source, D79): events read from iCalendar
// text (RFC 5545) and their times in a range, repeating ones included, and the days of a month as the popup draws
// them. Plain functions, so they test offscreen with fixed dates.
//
// Repeating events: RRULE with FREQ DAILY, WEEKLY, MONTHLY or YEARLY, INTERVAL, COUNT, UNTIL, BYDAY (weekly: the
// days of the week; monthly: "2MO", "-1FR" or plain days) and BYMONTHDAY (monthly); EXDATE leaves times out, and an
// event with a RECURRENCE-ID replaces its series' time. A rule with anything else (BYSETPOS, BYWEEKNO, HOURLY...)
// shows its first time only. Times repeat in local time, as the clock on the wall does across a DST change. A TZID time
// is a time in that zone (the file's VTIMEZONE, its STANDARD and DAYLIGHT parts) and repeats on that zone's clock; a
// TZID the file does not describe is taken as local.
.pragma library

var DAY = 86400000;

function unfold(text) {
    return String(text || "").replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "");
}
function unescapeText(v) {
    return v.replace(/\\n/gi, " ").replace(/\\([,;\\])/g, "$1");
}
// "20261105T100000Z", "20261105T100000" (local, or in the head's TZID when `zones` describes it) or a date;
// {date, allDay, zone} or null. `zone` is the TZID's observances for a time in one (see icsZones), else null.
function icsDate(value, params, zones) {
    var m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(value || "");
    if (!m) return null;
    if (!m[4]) return { date: new Date(+m[1], +m[2] - 1, +m[3]), allDay: true, zone: null };
    if (m[7]) return { date: new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])), allDay: false, zone: null };
    var zone = (zones || {})[tzid(params)] || null;
    if (zone) return { date: zoneTime(zone, Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])), allDay: false, zone: zone };
    return { date: new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]), allDay: /VALUE=DATE(;|$)/.test(params || ""),
             zone: null };
}

// ---- time zones (VTIMEZONE) ----
// Wall-clock times here are written as if in UTC ("floating"): Date.UTC of the fields a clock in the zone shows.
// The TZID in a property's head ("DTSTART;TZID=Europe/Berlin", quoted or not); "" without one.
function tzid(head) {
    var m = /;TZID=(?:"([^"]*)"|([^;:]*))/i.exec(head || "");
    return m ? (m[1] !== undefined ? m[1] : m[2]) : "";
}
// "+0530", "-0800", "+010000" in milliseconds; null for anything else
function icsOffset(value) {
    var m = /^([+-])(\d{2})(\d{2})(\d{2})?$/.exec(String(value || "").trim());
    if (!m) return null;
    var ms = ((+m[2] * 60 + +m[3]) * 60 + +(m[4] || 0)) * 1000;
    return m[1] === "-" ? -ms : ms;
}
// a local DTSTART or RDATE as a floating time; null when it is not one
function floating(value) {
    var m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2}))?$/.exec(value || "");
    return m ? Date.UTC(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0)) : null;
}
// The VTIMEZONEs in unfolded lines as {TZID: [{offset, before, start, rule, rdates}]}: one entry per STANDARD or
// DAYLIGHT part; `offset` is TZOFFSETTO and `before` TZOFFSETFROM (ms), `start` and `rdates` floating times, `rule` the
// yearly RRULE's {month, byDay: [{n, day}], byMonthDay: [], until (ms or null)} or null.
function icsZones(lines) {
    var zones = {};
    var id = null, list = null, cur = null;
    lines.forEach(function (line) {
        if (line === "BEGIN:VTIMEZONE") { id = ""; list = []; return; }
        if (line === "END:VTIMEZONE") {
            if (id && list.length) zones[id] = list;
            id = list = cur = null;
            return;
        }
        if (list === null) return;
        if (line === "BEGIN:STANDARD" || line === "BEGIN:DAYLIGHT") { cur = { rdates: [] }; return; }
        if (line === "END:STANDARD" || line === "END:DAYLIGHT") {
            if (cur && cur.offset !== null && cur.offset !== undefined && cur.start !== null && cur.start !== undefined)
                list.push({ offset: cur.offset, before: cur.before ?? cur.offset, start: cur.start,
                            rule: cur.rrule ? zoneRule(cur.rrule, cur.start) : null, rdates: cur.rdates });
            cur = null;
            return;
        }
        var colon = line.indexOf(":");
        if (colon < 0) return;
        var name = line.substring(0, colon).split(";")[0].toUpperCase(), value = line.substring(colon + 1);
        if (!cur) {
            if (name === "TZID") id = value;
            return;
        }
        if (name === "DTSTART") cur.start = floating(value);
        else if (name === "TZOFFSETTO") cur.offset = icsOffset(value);
        else if (name === "TZOFFSETFROM") cur.before = icsOffset(value);
        else if (name === "RRULE") cur.rrule = value;
        else if (name === "RDATE") value.split(",").forEach(function (v) {
            var t = floating(v);
            if (t !== null) cur.rdates.push(t);
        });
    });
    return zones;
}
// A zone part's RRULE ("FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU"), on the part's DTSTART's month and day when it names none;
// null when it is not yearly.
function zoneRule(value, start) {
    var r = rule(value.split(";").filter(function (p) { return !/^BYMONTH=/i.test(p); }).join(";"));
    var month = /(?:^|;)BYMONTH=(\d+)/i.exec(value);
    if (!r || r.freq !== "YEARLY") return null;
    var s = new Date(start);
    return { month: month ? +month[1] - 1 : s.getUTCMonth(), day: s.getUTCDate(), byDay: r.byDay,
             byMonthDay: r.byMonthDay, until: r.until ? r.until.date.getTime() : null };
}
// When a zone part's rule starts in `year`, as a floating time (at its DTSTART's time of day); null when it does not.
function zoneOnset(part, year) {
    var r = part.rule, s = new Date(part.start);
    var length = new Date(Date.UTC(year, r.month + 1, 0)).getUTCDate();
    var days = [];
    for (var d = 1; d <= length; d++) days.push(d);
    if (r.byMonthDay.length) days = days.filter(function (d) {
        return r.byMonthDay.some(function (md) { return md === d || length + md + 1 === d; });
    });
    var pick = r.day <= length ? r.day : undefined;    // DTSTART is on its rule (RFC 5545)
    if (r.byDay.length) {               // one weekday: a zone changes once a year
        var b = r.byDay[0];
        var matches = days.filter(function (d) { return new Date(Date.UTC(year, r.month, d)).getUTCDay() === b.day; });
        pick = b.n === 0 ? matches[0] : b.n > 0 ? matches[b.n - 1] : matches[matches.length + b.n];
    }
    if (pick === undefined) return null;
    var t = Date.UTC(year, r.month, pick, s.getUTCHours(), s.getUTCMinutes(), s.getUTCSeconds());
    return t < part.start || (r.until !== null && t - part.before > r.until) ? null : t;
}
// The UTC offset (ms) in a zone at a floating time: the offset of the part that began last before it (its DTSTART,
// an RDATE, or its rule this year or last); before them all, the earliest part's TZOFFSETFROM.
function zoneOffset(zone, wall) {
    var best = null, offset = null;
    var year = new Date(wall).getUTCFullYear();
    zone.forEach(function (part) {
        var onsets = [part.start].concat(part.rdates);
        if (part.rule) onsets.push(zoneOnset(part, year), zoneOnset(part, year - 1));
        onsets.forEach(function (t) {
            if (t !== null && t <= wall && (best === null || t > best)) { best = t; offset = part.offset; }
        });
    });
    if (offset !== null) return offset;
    var first = zone.reduce(function (a, b) { return b.start < a.start ? b : a; });
    return first.before;
}
// a floating time in a zone as a Date
function zoneTime(zone, wall) {
    return new Date(wall - zoneOffset(zone, wall));
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
// null), zone (its DTSTART's, or null)}]. `end` is DTEND, or DTSTART plus DURATION, or for an event with neither its
// start (a day for an all-day one).
function icsEvents(text) {
    var out = [];
    var cur = null;
    var lines = unfold(text).split("\n");
    var zones = icsZones(lines);
    lines.forEach(function (line) {
        if (line === "BEGIN:VEVENT") { cur = { exdates: [] }; return; }
        if (line === "END:VEVENT") {
            if (cur && cur.start) {
                var start = cur.start.date, allDay = cur.start.allDay;
                var end = cur.end ? cur.end.date : cur.duration ? new Date(start.getTime() + cur.duration)
                        : new Date(start.getTime() + (allDay ? DAY : 0));
                if (end < start) end = start;
                out.push({ title: cur.title || "Event", start: start, end: end, allDay: allDay, rule: rule(cur.rrule),
                           exdates: cur.exdates, uid: cur.uid || "", recurrenceId: cur.recurrenceId ?? null,
                           zone: cur.start.zone });
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
        else if (name === "DTSTART") cur.start = icsDate(value, head, zones);
        else if (name === "DTEND") cur.end = icsDate(value, head, zones);
        else if (name === "DURATION") cur.duration = icsDuration(value);
        else if (name === "RRULE") cur.rrule = value;
        else if (name === "UID") cur.uid = value;
        else if (name === "RECURRENCE-ID") {
            var r = icsDate(value, head, zones);
            if (r) cur.recurrenceId = r.date.getTime();
        } else if (name === "EXDATE") value.split(",").forEach(function (v) {
            var d = icsDate(v, head, zones);
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
// A Date as a zone's clock shows it, made a local Date with those fields; and back (a local Date's fields read on the
// zone's clock).
function wallClock(zone, date) {
    var w = new Date(date.getTime() + zoneOffset(zone, date.getTime() + zoneOffset(zone, date.getTime())));
    return new Date(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate(), w.getUTCHours(), w.getUTCMinutes(), w.getUTCSeconds());
}
function inZone(zone, local) {
    return zoneTime(zone, Date.UTC(local.getFullYear(), local.getMonth(), local.getDate(), local.getHours(),
                                   local.getMinutes(), local.getSeconds()));
}
// The start times a rule makes, in order, while `more(time)`. Without a COUNT it skips the periods that end before
// `from`; a cap ends a rule that has gone wrong.
// An event in a zone repeats on that zone's clock: the times are made from its wall-clock start, then placed in the zone.
function ruleTimes(e, from, more) {
    var r = e.rule, s = e.zone ? wallClock(e.zone, e.start) : e.start, out = [];
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
            var t = e.zone ? inZone(e.zone, list[i]) : list[i];
            if (t < e.start) continue;
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

// one time of an event, with where it came from (an evolution-data-server event's calendar and uid, D95)
function occurrence(e, start, end) {
    return { title: e.title, start: start, end: end, allDay: e.allDay, source: e.source || "", uid: e.uid || "" };
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
            if (on(e.start, e.end)) out.push(occurrence(e, e.start, e.end));
            return;
        }
        ruleTimes(e, from, function (t) { return t < to; }).forEach(function (t) {
            var end = new Date(t.getTime() + length);
            if (e.exdates.indexOf(t.getTime()) >= 0 || replaced[e.uid + "@" + t.getTime()] || !on(t, end)) return;
            out.push(occurrence(e, t, end));
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

// ---- evolution-data-server (D95): what native/calendar.c (rutile-calendar) prints ----
// The helper: RUTILE_CALENDAR's, or the one built beside the shell.
function helperPath(env, shellDir) {
    return env || (shellDir + "/../build/rutile-calendar");
}
// The command that prints the events on between two Dates.
function edsCommand(helper, from, to) {
    return [helper, "events", String(Math.floor(from.getTime() / 1000)), String(Math.ceil(to.getTime() / 1000))];
}
// Its lines (one JSON object each) as events like icsEvents' (each time on its own: EDS expands repeats). A line
// that is not one is left out.
function edsEvents(text) {
    var out = [];
    String(text || "").split("\n").forEach(function (line) {
        if (line === "") return;
        var o;
        try { o = JSON.parse(line); } catch (e) { return; }
        if (!o || typeof o.start !== "number" || typeof o.end !== "number") return;
        out.push({ title: o.title || "Event", start: new Date(o.start * 1000), end: new Date(Math.max(o.start, o.end) * 1000),
                   allDay: o.allDay === true, rule: null, exdates: [], uid: o.uid || "", recurrenceId: null,
                   source: o.source || "" });
    });
    return out;
}
// What GNOME Calendar's --uuid opens: "<calendar>:<event uid>", for an evolution-data-server event; "" otherwise.
function eventUuid(e) {
    return e.source && e.uid ? e.source + ":" + e.uid : "";
}

// ---- adding an event (D101) ----
// The calendars an event can go to, from `rutile-calendar sources`: [{source, name, color, isDefault}], the
// data server's default first. Birthdays (made from contacts) and weather calendars are read-only and left out.
function edsCalendars(text) {
    var out = [];
    String(text || "").split("\n").forEach(function (line) {
        var o;
        try { o = JSON.parse(line); } catch (e) { return; }
        if (!o || !o.source || o.backend === "contacts" || o.backend === "weather") return;
        out.push({ source: o.source, name: o.name || o.source, color: o.color || "", isDefault: o.default === true });
    });
    return out.sort(function (a, b) { return (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0); });
}
// A time of day as typed ("9", "09:30", "9.30", "930", "21:30", "9pm", "9:30 AM") as minutes after midnight; -1
// when it is not one.
function parseClock(text) {
    var m = /^\s*(\d{1,2})(?:[:.]?(\d{2}))?\s*([ap])?\.?\s*m?\.?\s*$/i.exec(String(text || ""));
    if (!m) return -1;
    var h = parseInt(m[1], 10), min = m[2] !== undefined ? parseInt(m[2], 10) : 0;
    if (min > 59) return -1;
    if (m[3]) {
        if (h < 1 || h > 12) return -1;
        h = h % 12 + (m[3].toLowerCase() === "p" ? 12 : 0);
    } else if (h > 23) {
        return -1;
    }
    return h * 60 + min;
}
// Minutes after midnight as the clock shows them ("9:30", "21:30" or "9:30 PM").
function clockText(minutes, use24h) {
    var h = Math.floor(minutes / 60) % 24, m = minutes % 60, mm = (m < 10 ? "0" : "") + m;
    if (use24h) return h + ":" + mm;
    return ((h + 11) % 12 + 1) + ":" + mm + (h < 12 ? " AM" : " PM");
}
// When a new event on `day` starts unless changed: the next full hour today (at most 23:00), else 9:00.
function suggestedStart(day, now) {
    if (!sameDay(day, now)) return 9 * 60;
    return Math.min(23, now.getHours() + 1) * 60;
}
// The new event's times from the form: {start, end} (Dates) or {error}. All day: that day, to the next day's start.
// An end before the start is an error; an end at midnight ("0:00") is the end of the day.
function newEventTimes(day, allDay, startText, endText) {
    var d = startOfDay(day);
    if (allDay) return { start: d, end: new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1) };
    var s = parseClock(startText), e = parseClock(endText);
    if (s < 0) return { error: "Type a start time, like 9:30" };
    if (e < 0) return { error: "Type an end time, like 10:30" };
    if (e === 0) e = 24 * 60;
    if (e <= s) return { error: "It ends before it starts" };
    return { start: new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, s),
             end: new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, e) };
}
// The command that adds it (rutile-calendar add).
function addCommand(helper, source, allDay, start, end, title) {
    return [helper, "add", source, allDay ? "allday" : "timed", String(Math.round(start.getTime() / 1000)),
            String(Math.round(end.getTime() / 1000)), title];
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
        return { title: o.title, time: time, uuid: eventUuid(o) };
    });
}
