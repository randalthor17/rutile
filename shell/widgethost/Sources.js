// The widget data sources' values (plan 4.2, D79; fields in widgets/sources.json), worked out from what each
// reads (a date, UPower's numbers, /proc's text, Open-Meteo's JSON, an .ics file) by plain functions, so they test
// offscreen with fixed inputs. The QML in sources/ only gathers the inputs and calls these.
.pragma library
.import "../bar/ClockText.js" as ClockText
.import "../calendar/Calendar.js" as Calendar

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

// ---- system: /proc/stat, /proc/meminfo, /proc/uptime, /proc/loadavg, /proc/net/dev, df of / and the processors'
// frequencies, one after the other (D87) ----
function procSample(text) {
    var out = { cpu: null, cores: [], memTotal: 0, memAvailable: 0, swapTotal: 0, swapFree: 0, uptime: 0, load: "",
                rx: 0, tx: 0, disk: null, freqs: [] };
    String(text || "").split("\n").forEach(function (line) {
        var f = line.trim().split(/\s+/);
        if (/^cpu[0-9]*$/.test(f[0]) && f.length >= 5) {
            var n = f.slice(1).map(Number);
            var total = n.slice(0, 8).reduce(function (a, b) { return a + b; }, 0);   // up to steal: guest is in user
            var ticks = { idle: n[3] + (n[4] || 0), total: total };
            if (f[0] === "cpu") out.cpu = ticks;
            else out.cores.push(ticks);
        } else if (f[0] === "MemTotal:") {
            out.memTotal = Number(f[1]);
        } else if (f[0] === "MemAvailable:") {
            out.memAvailable = Number(f[1]);
        } else if (f[0] === "SwapTotal:") {
            out.swapTotal = Number(f[1]);
        } else if (f[0] === "SwapFree:") {
            out.swapFree = Number(f[1]);
        } else if (f.length >= 17 && /^[^:]+:$/.test(f[0]) && /^[0-9]+$/.test(f[1])) {
            // /proc/net/dev: received bytes, then sent bytes 8 columns on; the loopback is not the network
            if (f[0] !== "lo:") { out.rx += Number(f[1]); out.tx += Number(f[9]); }
        } else if (f.length === 6 && f[5] === "/" && /^[0-9]+$/.test(f[1])) {
            out.disk = { total: Number(f[1]), used: Number(f[2]), free: Number(f[3]) };      // df -P -B1 /
        } else if (f[0] === "freq" && /^[0-9]+$/.test(f[1])) {
            out.freqs.push(Number(f[1]));                                                       // kHz
        } else if (f.length === 2 && /^[0-9.]+$/.test(f[0]) && /^[0-9.]+$/.test(f[1])) {
            out.uptime = Number(f[0]);
        } else if (f.length === 5 && f[3].indexOf("/") > 0) {
            out.load = f[0];
        }
    });
    return out;
}
// The processor's name from /proc/cpuinfo ("model name", or ARM's "Hardware"/"Model"), without the trademarks,
// core count and clock: "AMD Ryzen 5 7600", "Intel Core i7-12700K"; "" when there is none.
function cpuName(text) {
    var m = /^(?:model name|Hardware|Model)\s*:\s*(.+)$/m.exec(String(text || ""));
    if (!m) return "";
    return m[1].replace(/\((R|TM|tm|r)\)/g, "").replace(/\s+@\s*[0-9.]+\s*GHz/i, "")
               .replace(/\s+[0-9]+-Core Processor/i, "").replace(/\s+(CPU|Processor)\b/gi, "")
               .replace(/\s+with Radeon.*$/i, "").replace(/\s+/g, " ").trim();
}
function gigabytes(kb) {
    var g = kb / 1048576;
    return (g >= 10 ? Math.round(g) : Math.round(g * 10) / 10) + " GB";
}
function round1(x) {
    return Math.round(x * 10) / 10;
}
// Bytes per second as text: 820 KB/s, 12.4 MB/s.
function rate(bytesPerSecond) {
    var kb = bytesPerSecond / 1024;
    if (kb < 1000) return Math.round(kb) + " KB/s";
    var mb = kb / 1024;
    return (mb >= 100 ? Math.round(mb) : round1(mb)) + " MB/s";
}
function busy(prev, cur) {
    if (!prev || !cur || cur.total <= prev.total) return 0;
    return Math.max(0, Math.min(1, 1 - (cur.idle - prev.idle) / (cur.total - prev.total)));
}
// `list` with `value` added at the end, at most `max` long (the last `max` samples, for line and bar charts).
function pushed(list, value, max) {
    var out = (list || []).concat([value]);
    return out.length > max ? out.slice(out.length - max) : out;
}
// How many samples a history keeps: the source's `history` option, 60 (a minute at one a second) when not given.
function historyLength(options) {
    var n = Number(options && options.history);
    return n >= 2 && n <= 300 ? Math.round(n) : 60;
}
// How often system, gpu and sensors read, in ms: the source's `every` option (0.5 to 10 seconds), 1 s when not given.
function pollInterval(options) {
    var s = Number(options && options.every);
    return s >= 0.5 && s <= 10 ? Math.round(s * 1000) : 1000;
}
// The values from two samples a moment apart (the first one alone: no processor use yet); `seconds` between them
// for the network's rates; `previousValue` for the histories.
function system(previous, current, seconds, previousValue, options, name) {
    var cpu = previous ? busy(previous.cpu, current.cpu) : 0;
    var mem = current.memTotal > 0 ? (current.memTotal - current.memAvailable) / current.memTotal : 0;
    var swap = current.swapTotal > 0 ? (current.swapTotal - current.swapFree) / current.swapTotal : 0;
    var cores = current.cores.map(function (c, i) { return Math.round(busy(previous && previous.cores[i], c) * 100); });
    var dt = seconds > 0 ? seconds : 0;
    var down = previous && dt > 0 ? Math.max(0, current.rx - previous.rx) / dt : 0;
    var up = previous && dt > 0 ? Math.max(0, current.tx - previous.tx) / dt : 0;
    var d = current.disk || { total: 0, used: 0, free: 0 };
    var diskFraction = d.used + d.free > 0 ? d.used / (d.used + d.free) : 0;
    var ghz = current.freqs.length ? Math.max.apply(null, current.freqs) / 1e6 : 0;
    var max = historyLength(options);
    var pv = previousValue || {};
    var usedKb = current.memTotal - current.memAvailable;
    return {
        cpu: Math.round(cpu * 100), cpuFraction: cpu, cores: cores, cpuName: name || "",
        cpuFrequency: ghz > 0 ? ghz.toFixed(1) + " GHz" : "",
        cpuHistory: pushed(pv.cpuHistory, Math.round(cpu * 100), max),
        memory: Math.round(mem * 100), memoryFraction: mem,
        memoryUsed: gigabytes(usedKb), memoryTotal: gigabytes(current.memTotal),
        memoryUsedGB: round1(usedKb / 1048576), memoryFreeGB: round1(current.memAvailable / 1048576),
        memoryHistory: pushed(pv.memoryHistory, Math.round(mem * 100), max),
        swap: Math.round(swap * 100), swapFraction: swap,
        swapUsed: gigabytes(current.swapTotal - current.swapFree), swapTotal: gigabytes(current.swapTotal),
        disk: Math.round(diskFraction * 100), diskFraction: diskFraction,
        diskUsed: gigabytes(d.used / 1024), diskFree: gigabytes(d.free / 1024), diskTotal: gigabytes(d.total / 1024),
        diskUsedGB: round1(d.used / 1073741824), diskFreeGB: round1(d.free / 1073741824),
        download: rate(down), upload: rate(up),
        downloadRate: Math.round(down / 1024), uploadRate: Math.round(up / 1024),
        downloadHistory: pushed(pv.downloadHistory, Math.round(down / 1024), max),
        uploadHistory: pushed(pv.uploadHistory, Math.round(up / 1024), max),
        uptime: duration(current.uptime), load: current.load
    };
}

// ---- gpu: each card's sysfs and nvidia-smi's line, if there is one (D87) ----
// The script prints, per card: "card NAME", "vendor 0x1002", "driver amdgpu", amdgpu's "<file> <value>"
// (gpu_busy_percent, mem_info_vram_*), "sclk <the starred pp_dpm_sclk line>" (amdgpu) or "gtfreq <MHz>" (i915, xe),
// and "<hwmon file> <value> <its label>" (temperatures, power, energy, fan: amdgpu, nouveau, Intel's discrete cards);
// nvidia-smi (NVIDIA's own driver) prints "nvidia <use>, <vram used MiB>, <total MiB>, <°C>, <W>, <fan %>, <MHz>, <name>".
// What a driver does not give stays null and its fields are left out.
function gpuSample(text) {
    var cards = [], card = null;
    var blank = function (name) {
        return { name: name, vendor: "", driver: "", busy: null, vramTotal: 0, vramUsed: 0, clock: 0, temps: {},
                 power: null, energy: null, fan: null, title: "" };
    };
    String(text || "").split("\n").forEach(function (line) {
        var f = line.trim().split(/\s+/);
        if (f[0] === "card") {
            card = blank(f[1]);
            cards.push(card);
        } else if (f[0] === "nvidia") {
            var parts = line.trim().substring(7).split(",");
            var v = parts.slice(0, 7).map(function (x) { return Number(x.trim()); });
            var nv = blank("nvidia" + cards.filter(function (c) { return c.driver === "nvidia-smi"; }).length);
            nv.vendor = "NVIDIA"; nv.driver = "nvidia-smi";
            nv.busy = isFinite(v[0]) ? v[0] : null;
            nv.vramUsed = (v[1] || 0) * 1048576; nv.vramTotal = (v[2] || 0) * 1048576;
            if (isFinite(v[3])) nv.temps.edge = v[3];
            nv.power = isFinite(v[4]) ? v[4] : null; nv.fan = isFinite(v[5]) ? v[5] : null; nv.clock = v[6] || 0;
            nv.title = parts.slice(7).join(",").trim();
            cards.push(nv);
            card = null;
        } else if (card) {
            if (f[0] === "vendor") card.vendor = { "0x1002": "AMD", "0x10de": "NVIDIA", "0x8086": "Intel" }[f[1]] || f[1];
            else if (f[0] === "driver") card.driver = f[1] || "";
            else if (f[0] === "gpu_busy_percent") card.busy = Number(f[1]);
            else if (f[0] === "mem_info_vram_total") card.vramTotal = Number(f[1]);
            else if (f[0] === "mem_info_vram_used") card.vramUsed = Number(f[1]);
            else if (f[0] === "sclk") { var m = /([0-9]+)\s*Mhz/i.exec(line); if (m) card.clock = Number(m[1]); }
            else if (f[0] === "gtfreq" && /^[0-9]+$/.test(f[1])) card.clock = Number(f[1]);
            else if (/^temp[0-9]+_input$/.test(f[0])) card.temps[f[2] || f[0]] = Number(f[1]) / 1000;
            else if (f[0] === "power1_average" || (f[0] === "power1_input" && card.power === null)) card.power = Number(f[1]) / 1e6;
            else if (f[0] === "energy1_input" && /^[0-9]+$/.test(f[1])) card.energy = Number(f[1]);
            else if (f[0] === "fan1_input") card.fan = Number(f[1]);
        }
    });
    return cards;
}
// The names script's lines ("name CARD VENDOR:DEVICE TEXT", TEXT from amdgpu.ids, or "pci " and pci.ids' text) as
// {card: name}: amdgpu.ids' marketing name as it is; pci.ids' "Navi 44 [Radeon RX 9060 XT]" as its bracket, after
// the vendor; nothing found: the vendor and the PCI id.
function gpuNames(text) {
    var out = {};
    var vendors = { "1002": "AMD", "10de": "NVIDIA", "8086": "Intel" };
    String(text || "").split("\n").forEach(function (line) {
        var m = /^name\s+(\S+)\s+([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\s*(.*)$/.exec(line.trim());
        if (!m) return;
        var vendor = vendors[m[2].toLowerCase()] || m[2];
        var t = m[4].trim();
        if (t.indexOf("pci ") === 0) {
            var b = /\[([^\]]+)\]/.exec(t);
            t = vendor + " " + (b ? b[1] : t.substring(4));
        }
        out[m[1]] = t || vendor + " " + m[2] + ":" + m[3];
    });
    return out;
}
// The card a widget shows: the one its `card` option names, else the one with the most video memory (a discrete
// card over the processor's own graphics), else the first.
function pickCard(cards, options) {
    var named = options && options.card;
    if (named) return cards.find(function (c) { return c.name === named; }) || null;
    return cards.reduce(function (best, c) { return !best || c.vramTotal > best.vramTotal ? c : best; }, null);
}
// `previous` and `seconds`: the last sample, for power from an energy counter (Intel's discrete cards).
function gpu(cards, options, previousValue, previous, seconds, names) {
    var c = pickCard(cards, options);
    var pv = previousValue || {};
    var max = historyLength(options);
    if (!c) return { available: false };
    var out = { available: true, name: c.title || (names && names[c.name]) || (c.vendor + " " + c.name) };
    if (c.busy !== null) {
        out.usage = Math.round(c.busy);
        out.usageFraction = c.busy / 100;
        out.usageHistory = pushed(pv.usageHistory, Math.round(c.busy), max);
    }
    if (c.vramTotal > 0) {
        var vram = c.vramUsed / c.vramTotal;
        out.vram = Math.round(vram * 100);
        out.vramFraction = vram;
        out.vramUsed = gigabytes(c.vramUsed / 1024);
        out.vramTotal = gigabytes(c.vramTotal / 1024);
        out.vramUsedGB = round1(c.vramUsed / 1073741824);
        out.vramFreeGB = round1((c.vramTotal - c.vramUsed) / 1073741824);
    }
    if (c.clock > 0) out.clock = c.clock >= 1000 ? (c.clock / 1000).toFixed(2) + " GHz" : c.clock + " MHz";
    var temp = c.temps.edge !== undefined ? c.temps.edge : c.temps[Object.keys(c.temps)[0]];
    if (temp !== undefined) {
        out.temperature = Math.round(temp);
        out.temperatureHistory = pushed(pv.temperatureHistory, Math.round(temp), max);
    }
    if (c.temps.junction !== undefined) out.hotspot = Math.round(c.temps.junction);
    if (c.temps.mem !== undefined) out.memoryTemperature = Math.round(c.temps.mem);
    var power = c.power;
    if (power === null && c.energy !== null && seconds > 0) {
        var before = (previous || []).find(function (p) { return p.name === c.name; });
        if (before && before.energy !== null && c.energy >= before.energy) power = (c.energy - before.energy) / 1e6 / seconds;
    }
    if (power !== null) {
        out.power = Math.round(power);
        out.powerHistory = pushed(pv.powerHistory, Math.round(power), max);
    }
    if (c.fan !== null) out.fan = Math.round(c.fan);
    return out;
}

// ---- sensors: every hwmon temperature ("hwmon NAME", then "<tempN_input> <value> <label>") and RAPL's energy
// counter when it can be read ("rapl <microjoules>"; root only on most systems) (D87) ----
function sensorsSample(text) {
    var out = { temps: [], energy: null }, chip = "";
    String(text || "").split("\n").forEach(function (line) {
        var f = line.trim().split(/\s+/);
        if (f[0] === "hwmon") chip = f[1] || "";
        else if (f[0] === "rapl" && /^[0-9]+$/.test(f[1])) out.energy = Number(f[1]);
        else if (/^temp[0-9]+_input$/.test(f[0]) && /^-?[0-9]+$/.test(f[1]))
            out.temps.push({ chip: chip, sensor: f[0].replace("_input", ""), label: f.slice(2).join(" "), value: Number(f[1]) / 1000 });
    });
    return out;
}
var CPU_CHIPS = [["k10temp", "Tctl"], ["k10temp", "Tdie"], ["zenpower", "Tdie"], ["coretemp", "Package id 0"],
                 ["cpu_thermal", ""], ["acpitz", ""]];
function sensors(previous, current, seconds, previousValue, options) {
    var pv = previousValue || {};
    var max = historyLength(options);
    var find = function (chip, label) {
        return current.temps.find(function (t) { return t.chip === chip && (label === "" || t.label === label); });
    };
    var cpu = null;
    for (var i = 0; i < CPU_CHIPS.length && !cpu; i++) cpu = find(CPU_CHIPS[i][0], CPU_CHIPS[i][1]);
    var nvme = find("nvme", "Composite") || find("nvme", "");
    // plausible readings only: boards report -55 °C or 0 for sensors that are not there
    var real = current.temps.filter(function (t) { return t.value > 0 && t.value < 150; });
    var out = {
        temperatures: real.map(function (t) { return { name: t.chip + " " + (t.label || t.sensor), value: Math.round(t.value) }; }),
        hottest: real.length ? Math.round(Math.max.apply(null, real.map(function (t) { return t.value; }))) : 0
    };
    if (cpu) {
        out.cpu = Math.round(cpu.value);
        out.cpuHistory = pushed(pv.cpuHistory, Math.round(cpu.value), max);
    }
    if (nvme) out.nvme = Math.round(nvme.value);
    if (previous && previous.energy !== null && current.energy !== null && seconds > 0 && current.energy >= previous.energy)
        out.cpuPower = Math.round((current.energy - previous.energy) / 1e6 / seconds);
    return out;
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

// ---- calendar: events from iCalendar text (RFC 5545), several files' text one after the other; Calendar.js reads
// them, repeating ones included (D93) ----
function icsEvents(text) {
    return Calendar.icsEvents(text);
}
// The events from now to `days` ahead (today's all-day ones included), soonest first, as the source's values.
function calendar(events, now, days, use24h, locale) {
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var end = new Date(startOfToday.getTime() + (days || 7) * 86400000);
    var coming = Calendar.occurrences(events, startOfToday, end).filter(function (e) {
        return e.allDay ? e.start >= startOfToday : e.start >= now;
    });
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
