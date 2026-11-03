// The widget data sources' values (plan 4.2, D79; fields in widgets/sources.json), worked out from what each
// reads (a date, UPower's numbers, /proc's text, Open-Meteo's JSON, an .ics file) by plain functions, so they test
// offscreen with fixed inputs. The QML in sources/ only gathers the inputs and calls these.
.pragma library
.import "../bar/ClockText.js" as ClockText

// "3 h 12 min", "45 min", "2 d 4 h"; "" for nothing or unknown.
function duration(seconds) {
    if (!(seconds > 0)) return "";
    var m = Math.round(seconds / 60);
    if (m >= 24 * 60) return Math.floor(m / 1440) + " d " + Math.floor((m % 1440) / 60) + " h";
    return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min";
}
function pad(n) {
    return (n < 10 ? "0" : "") + n;
}

// ---- clock ----
// `now` a Date; utcOffset (hours) shows another place's time; use24h as the locale says.
function clock(now, options, use24h, locale) {
    var d = now;
    if (options && typeof options.utcOffset === "number") {
        var utc = now.getTime() + now.getTimezoneOffset() * 60000;
        d = new Date(utc + options.utcOffset * 3600000);
    }
    var secs = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds();
    return {
        time: ClockText.time(d, use24h), seconds: d.getSeconds(), date: ClockText.date(d, locale),
        weekday: locale.toString(d, "dddd"), day: d.getDate(), month: locale.toString(d, "MMMM"),
        year: d.getFullYear(), hour: d.getHours(), minute: d.getMinutes(), dayProgress: secs / 86400
    };
}

// ---- battery ----
// b: {present, percentage (0..1), state: charging | pending | full | empty | discharging, timeToFull, timeToEmpty}
function battery(b) {
    if (!b || !b.present) return { present: false };
    var level = Math.round(b.percentage * 100);
    var charging = b.state === "charging";
    var status = charging ? "Charging" : b.state === "full" ? "Full" : b.state === "pending" ? "Not charging"
               : "Discharging";
    return {
        present: true, level: level, fraction: Math.max(0, Math.min(1, b.percentage)), charging: charging,
        status: status, timeLeft: duration(charging ? b.timeToFull : b.state === "discharging" ? b.timeToEmpty : 0)
    };
}

// ---- system: /proc/stat, /proc/meminfo, /proc/uptime and /proc/loadavg, one after the other ----
// {cpu: {idle, total} (the counters since boot), memTotal, memAvailable (kB), uptime (s), load}
function procSample(text) {
    var out = { cpu: null, memTotal: 0, memAvailable: 0, uptime: 0, load: "" };
    String(text || "").split("\n").forEach(function (line) {
        var f = line.trim().split(/\s+/);
        if (f[0] === "cpu") {
            var n = f.slice(1).map(Number);
            var total = n.slice(0, 8).reduce(function (a, b) { return a + b; }, 0);   // up to steal: guest is in user
            out.cpu = { idle: n[3] + (n[4] || 0), total: total };
        } else if (f[0] === "MemTotal:") {
            out.memTotal = Number(f[1]);
        } else if (f[0] === "MemAvailable:") {
            out.memAvailable = Number(f[1]);
        } else if (f.length === 2 && /^[0-9.]+$/.test(f[0]) && /^[0-9.]+$/.test(f[1])) {
            out.uptime = Number(f[0]);
        } else if (f.length === 5 && f[3].indexOf("/") > 0) {
            out.load = f[0];
        }
    });
    return out;
}
function gigabytes(kb) {
    var g = kb / 1048576;
    return (g >= 10 ? Math.round(g) : Math.round(g * 10) / 10) + " GB";
}
// The values from two samples a moment apart (the first one alone: no processor use yet).
function system(previous, current) {
    var cpu = 0;
    if (previous && previous.cpu && current.cpu && current.cpu.total > previous.cpu.total) {
        var dt = current.cpu.total - previous.cpu.total;
        cpu = Math.max(0, Math.min(1, 1 - (current.cpu.idle - previous.cpu.idle) / dt));
    }
    var mem = current.memTotal > 0 ? (current.memTotal - current.memAvailable) / current.memTotal : 0;
    return {
        cpu: Math.round(cpu * 100), cpuFraction: cpu, memory: Math.round(mem * 100), memoryFraction: mem,
        memoryUsed: gigabytes(current.memTotal - current.memAvailable), memoryTotal: gigabytes(current.memTotal),
        uptime: duration(current.uptime), load: current.load
    };
}

// ---- countdown ----
// "2026-12-25" or "2026-12-25T18:00", local time; null when malformed.
function localDate(text) {
    var m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(text || "");
    if (!m) return null;
    return new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0));
}
function countdown(now, options) {
    var target = localDate(options && options.target);
    if (!target) return {};
    var from = localDate(options.from);
    var left = Math.max(0, target.getTime() - now.getTime());
    var mins = Math.floor(left / 60000);
    var days = Math.floor(mins / 1440), hours = Math.floor((mins % 1440) / 60), minutes = mins % 60;
    var text = left === 0 ? "Now" : days > 0 ? days + (days === 1 ? " day " : " days ") + hours + " h"
             : hours > 0 ? hours + " h " + minutes + " min" : Math.max(1, minutes) + " min";
    var span = from ? target.getTime() - from.getTime() : 0;
    var progress = span > 0 ? Math.max(0, Math.min(1, (now.getTime() - from.getTime()) / span)) : (left === 0 ? 1 : 0);
    return { days: days, hours: hours, minutes: minutes, text: text, done: left === 0,
             remaining: span > 0 ? 1 - progress : 0, progress: progress };
}

// ---- media ----
// p: {name, playing, title, artist, album, art, position, length (seconds)}, or null
function media(p) {
    if (!p) return { playing: false, title: "", artist: "", album: "", art: "", progress: 0, player: "" };
    return { playing: !!p.playing, title: p.title || "", artist: p.artist || "", album: p.album || "",
             art: p.art || "", progress: p.length > 0 ? Math.max(0, Math.min(1, p.position / p.length)) : 0,
             player: p.name || "" };
}
// The player to show: the first that is playing, else the first.
function pickPlayer(players) {
    for (var i = 0; i < players.length; i++)
        if (players[i].playing) return players[i];
    return players.length ? players[0] : null;
}

// ---- weather (Open-Meteo, no key) ----
var WEATHER_URL = "https://api.open-meteo.com/v1/forecast";
// The place and units: the widget's options first, then Settings (widgets.latitude, .longitude, .units);
// null without a place.
function weatherPlace(options, settings) {
    options = options || {};
    settings = settings || {};
    var lat = typeof options.latitude === "number" ? options.latitude : settings.latitude;
    var lon = typeof options.longitude === "number" ? options.longitude : settings.longitude;
    if (typeof lat !== "number" || typeof lon !== "number") return null;
    return { latitude: lat, longitude: lon, units: options.units || settings.units || "metric" };
}
function weatherUrl(place, base) {
    var url = (base || WEATHER_URL) + "?latitude=" + place.latitude + "&longitude=" + place.longitude +
        "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day" +
        "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1";
    return place.units === "imperial" ? url + "&temperature_unit=fahrenheit&wind_speed_unit=mph" : url;
}
// WMO weather codes as Open-Meteo gives them: [text, symbol by day, symbol by night]
var CODES = {
    0: ["Clear", "clear_day", "clear_night"], 1: ["Mostly clear", "clear_day", "clear_night"],
    2: ["Partly cloudy", "partly_cloudy_day", "partly_cloudy_night"], 3: ["Cloudy", "cloud", "cloud"],
    45: ["Fog", "foggy", "foggy"], 48: ["Fog", "foggy", "foggy"],
    51: ["Drizzle", "rainy_light", "rainy_light"], 53: ["Drizzle", "rainy_light", "rainy_light"],
    55: ["Drizzle", "rainy_light", "rainy_light"], 56: ["Freezing drizzle", "weather_mix", "weather_mix"],
    57: ["Freezing drizzle", "weather_mix", "weather_mix"], 61: ["Light rain", "rainy_light", "rainy_light"],
    63: ["Rain", "rainy", "rainy"], 65: ["Heavy rain", "rainy_heavy", "rainy_heavy"],
    66: ["Freezing rain", "weather_mix", "weather_mix"], 67: ["Freezing rain", "weather_mix", "weather_mix"],
    71: ["Light snow", "weather_snowy", "weather_snowy"], 73: ["Snow", "weather_snowy", "weather_snowy"],
    75: ["Heavy snow", "snowing_heavy", "snowing_heavy"], 77: ["Snow grains", "weather_snowy", "weather_snowy"],
    80: ["Showers", "rainy", "rainy"], 81: ["Showers", "rainy", "rainy"], 82: ["Heavy showers", "rainy_heavy", "rainy_heavy"],
    85: ["Snow showers", "weather_snowy", "weather_snowy"], 86: ["Snow showers", "weather_snowy", "weather_snowy"],
    95: ["Thunderstorm", "thunderstorm", "thunderstorm"], 96: ["Thunderstorm, hail", "thunderstorm", "thunderstorm"],
    99: ["Thunderstorm, hail", "thunderstorm", "thunderstorm"]
};
// Open-Meteo's answer as the source's values; {} when it is not one.
function weather(doc, units) {
    var c = doc && doc.current;
    if (!c || typeof c.temperature_2m !== "number") return {};
    var code = CODES[c.weather_code] || ["Unknown", "thermostat", "thermostat"];
    var daily = doc.daily || {};
    var first = function (a) { return a && typeof a[0] === "number" ? Math.round(a[0]) : null; };
    return {
        temperature: Math.round(c.temperature_2m), apparent: Math.round(c.apparent_temperature),
        high: first(daily.temperature_2m_max), low: first(daily.temperature_2m_min),
        unit: units === "imperial" ? "°F" : "°C", humidity: Math.round(c.relative_humidity_2m),
        wind: Math.round(c.wind_speed_10m) + (units === "imperial" ? " mph" : " km/h"),
        condition: code[0], symbol: c.is_day === 0 ? code[2] : code[1]
    };
}

// ---- http ----
// Whether `url` starts with one of the allowed prefixes (Settings > Widgets); a prefix must name a host and path
// start ("https://api.example.org/"), so "https://api.example.org.evil/" is not allowed by "https://api.example.org".
function allowed(url, prefixes) {
    if (!/^https?:\/\/[^/]+\//.test(url || "")) return false;
    return (prefixes || []).some(function (p) {
        if (!/^https?:\/\/[^/]+\//.test(p)) return false;
        return url.indexOf(p) === 0;
    });
}

// ---- files ----
function files(text) {
    var t = String(text || "");
    var lines = t.split("\n");
    if (lines.length && lines[lines.length - 1] === "") lines.pop();
    var json;
    try {
        json = JSON.parse(t);
    } catch (e) {
        json = undefined;
    }
    var out = { text: t.substring(0, 2000), firstLine: lines.length ? lines[0] : "",
                lines: lines.slice(0, 50).map(function (l) { return { text: l }; }) };
    if (json !== null && typeof json === "object") out.json = json;
    return out;
}

// ---- calendar: single events from iCalendar text (RFC 5545), several files' text one after the other ----
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
// [{title, start: Date, allDay}] of the VEVENTs (a repeating one only at its first time)
function icsEvents(text) {
    var out = [];
    var cur = null;
    unfold(text).split("\n").forEach(function (line) {
        if (line === "BEGIN:VEVENT") { cur = {}; return; }
        if (line === "END:VEVENT") {
            if (cur && cur.start) out.push({ title: cur.title || "Event", start: cur.start.date, allDay: cur.start.allDay });
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
    });
    return out;
}
// The events from now to `days` ahead (today's all-day ones included), soonest first, as the source's values.
function calendar(events, now, days, use24h, locale) {
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var end = new Date(startOfToday.getTime() + (days || 7) * 86400000);
    var coming = events.filter(function (e) {
        return e.start < end && (e.allDay ? e.start >= startOfToday : e.start >= now);
    }).sort(function (a, b) { return a.start - b.start; });
    var list = coming.slice(0, 8).map(function (e) {
        var day = new Date(e.start.getFullYear(), e.start.getMonth(), e.start.getDate());
        var diff = Math.round((day - startOfToday) / 86400000);
        var date = diff === 0 ? "Today" : diff === 1 ? "Tomorrow" : ClockText.date(e.start, locale);
        var time = e.allDay ? "All day" : ClockText.time(e.start, use24h);
        return { title: e.title, date: date, time: time, when: date + ", " + time };
    });
    return { events: list, next: list.length ? list[0].title : "No events", nextWhen: list.length ? list[0].when : "",
             count: coming.length };
}
