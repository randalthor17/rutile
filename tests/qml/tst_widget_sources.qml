import QtQuick
import QtTest
import qs.common
import qs.widgethost
import "../qs/widgethost/Sources.js" as Sources
import "../qs/widgethost/WidgetSpec.js" as Spec
import "../qs/widgethost/SourceCatalog.js" as Catalog

// The widget data sources' values from fixed inputs (plan 4.2), and the renderer's use of them.
TestCase {
    id: root
    name: "WidgetSources"
    width: 400
    height: 600
    visible: true
    when: windowShown

    readonly property var en: Qt.locale("en_US")

    function readJson(rel) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }
    // every field a source's values have is in the catalog, and every catalog field is there
    function fieldsMatch(source, values) {
        compare(Object.keys(values).sort().join(), Object.keys(Catalog.sources[source].fields).sort().join(), source);
    }

    function test_duration() {
        compare(Sources.duration(0), "");
        compare(Sources.duration(-5), "");
        compare(Sources.duration(45 * 60), "45 min");
        compare(Sources.duration(3 * 3600 + 12 * 60), "3 h 12 min");
        compare(Sources.duration(2 * 86400 + 4 * 3600), "2 d 4 h");
    }

    function test_clock() {
        const now = new Date(2026, 10, 3, 14, 5, 30);
        const c = Sources.clock(now, {}, true, en);
        fieldsMatch("clock", c);
        compare(c.time, "14:05");
        compare(Sources.clock(now, {}, false, en).time, "2:05", "12-hour, as the clock pill");
        compare(c.date, "Tue, Nov 3");
        compare(c.weekday, "Tuesday");
        compare(c.month, "November");
        compare([c.day, c.year, c.hour, c.minute, c.seconds].join(), "3,2026,14,5,30");
        fuzzyCompare(c.dayProgress, (14 * 3600 + 5 * 60 + 30) / 86400, 1e-9);
        // a world clock: UTC+9 from this machine's UTC time
        const utcHour = (now.getUTCHours() + 9) % 24;
        compare(Sources.clock(now, { utcOffset: 9 }, true, en).hour, utcHour);
        compare(Sources.clock(now, { utcOffset: 5.5 }, true, en).minute, (now.getUTCMinutes() + 30) % 60, "half hours");
    }

    function test_battery() {
        compare(JSON.stringify(Sources.battery({ present: false })), '{"present":false}');
        const b = Sources.battery({ present: true, percentage: 0.643, state: "discharging", timeToEmpty: 7800, timeToFull: 0 });
        fieldsMatch("battery", b);
        compare([b.level, b.charging, b.status, b.timeLeft].join(), "64,false,Discharging,2 h 10 min");
        fuzzyCompare(b.fraction, 0.643, 1e-9);
        const c = Sources.battery({ present: true, percentage: 0.5, state: "charging", timeToEmpty: 0, timeToFull: 1800 });
        compare([c.charging, c.status, c.timeLeft].join(), "true,Charging,30 min");
        compare(Sources.battery({ present: true, percentage: 1, state: "full" }).status, "Full");
        compare(Sources.battery({ present: true, percentage: 0.8, state: "pending", timeToEmpty: 99 }).timeLeft, "",
                "plugged in, not charging: no time");
    }

    function test_system() {
        const proc = n => "cpu  " + n.join(" ") + "\ncpu0 1 2 3 4\nMemTotal:       16303112 kB\n" +
                          "MemFree:         1000000 kB\nMemAvailable:   10781884 kB\n11523.45 80000.12\n0.52 0.48 0.40 2/1234 5678\n";
        const a = Sources.procSample(proc([100, 0, 50, 800, 50, 0, 0, 0, 0, 0]));
        const b = Sources.procSample(proc([160, 0, 70, 900, 70, 0, 0, 0, 10, 0]));
        compare(a.cpu.total, 1000, "guest is already in user: not counted twice");
        const s = Sources.system(a, b);
        fieldsMatch("system", s);
        // 200 ticks passed, 120 of them idle or waiting: 40 % busy
        compare(s.cpu, 40);
        fuzzyCompare(s.cpuFraction, 0.4, 1e-9);
        compare(s.memory, 34);
        compare(s.memoryUsed, "5.3 GB");
        compare(s.memoryTotal, "16 GB");
        compare(s.uptime, "3 h 12 min");
        compare(s.load, "0.52");
        compare(Sources.system(null, b).cpu, 0, "one sample: no processor use yet");
    }

    function test_countdown() {
        const now = new Date(2026, 11, 20, 12, 0);
        const c = Sources.countdown(now, { target: "2026-12-25", from: "2026-12-15" });
        fieldsMatch("countdown", c);
        compare([c.days, c.hours, c.minutes, c.text, c.done].join(), "4,12,0,4 days 12 h,false");
        fuzzyCompare(c.progress, 0.55, 1e-9, "5.5 of 10 days");
        fuzzyCompare(c.remaining, 0.45, 1e-9);
        compare(Sources.countdown(now, { target: "2026-12-20T15:30" }).text, "3 h 30 min");
        compare(Sources.countdown(now, { target: "2026-12-21T18:00" }).text, "1 day 6 h");
        compare(Sources.countdown(now, { target: "2026-12-20T12:00:20" }).text, "1 min", "under a minute: 1 min");
        const done = Sources.countdown(now, { target: "2026-12-01" });
        compare([done.text, done.done, done.progress, done.remaining].join(), "Now,true,1,0");
        compare(Sources.countdown(now, { target: "2026-12-25" }).remaining, 0, "without from: no fractions");
        compare(JSON.stringify(Sources.countdown(now, { target: "Christmas" })), "{}");
    }

    function test_media() {
        const none = Sources.media(null);
        fieldsMatch("media", none);
        compare(none.playing, false);
        const players = [{ name: "mpv", playing: false, title: "A" }, { name: "Firefox", playing: true, title: "B", artist: "C",
                          art: "https://x/y.jpg", position: 30, length: 120 }];
        const m = Sources.media(Sources.pickPlayer(players));
        compare([m.player, m.title, m.artist, m.art, m.progress].join(), "Firefox,B,C,https://x/y.jpg,0.25");
        compare(Sources.pickPlayer([players[0]]).name, "mpv", "none playing: the first");
        compare(Sources.pickPlayer([]), null);
    }

    function test_weather() {
        compare(Sources.weatherPlace({}, {}), null, "no place: no weather");
        const place = Sources.weatherPlace({ latitude: 52.52 }, { latitude: 1, longitude: 13.41, units: "imperial" });
        compare(JSON.stringify(place), '{"latitude":52.52,"longitude":13.41,"units":"imperial"}', "the widget's first");
        const url = Sources.weatherUrl(place);
        verify(url.indexOf("https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.41&") === 0, url);
        verify(url.indexOf("temperature_unit=fahrenheit") > 0);
        verify(Sources.weatherUrl({ latitude: 1, longitude: 2, units: "metric" }).indexOf("fahrenheit") < 0);
        const doc = readJson("../data/open-meteo.json");
        const w = Sources.weather(doc, "metric");
        fieldsMatch("weather", w);
        compare([w.temperature, w.apparent, w.high, w.low, w.unit, w.humidity, w.wind, w.condition, w.symbol].join(),
                "8,5,11,3,°C,81,13 km/h,Partly cloudy,partly_cloudy_day");
        doc.current.is_day = 0;
        compare(Sources.weather(doc, "metric").symbol, "partly_cloudy_night");
        compare(Sources.weather(doc, "imperial").wind, "13 mph");
        compare(JSON.stringify(Sources.weather({ error: true }, "metric")), "{}");
    }

    function test_http_allowed() {
        const allow = ["https://api.frankfurter.app/", "http://localhost:8080/"];
        verify(Sources.allowed("https://api.frankfurter.app/latest?from=EUR", allow));
        verify(Sources.allowed("http://localhost:8080/stats.json", allow));
        verify(!Sources.allowed("https://api.frankfurter.app.evil.org/latest", allow), "another host");
        verify(!Sources.allowed("https://evil.org/?https://api.frankfurter.app/", allow));
        verify(!Sources.allowed("https://api.frankfurter.app/x", ["https://api.frankfurter.app"]),
               "a prefix without a path does not count: it would allow any host it starts");
        verify(!Sources.allowed("https://example.org/", []));
        verify(!Sources.allowed("file:///etc/passwd", ["file:///"]));
    }

    function test_files() {
        const f = Sources.files("one\ntwo\n");
        fieldsMatch("files", Object.assign({ json: {} }, f));
        compare([f.firstLine, f.lines.length, f.lines[1].text].join(), "one,2,two");
        verify(!("json" in f), "not JSON");
        compare(Sources.files('{"total": 7}').json.total, 7);
        compare(Sources.files("x".repeat(3000)).text.length, 2000);
        compare(Sources.files("").firstLine, "");
    }

    function test_calendar() {
        const ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:Dentist\\, Dr. A\r\nDTSTART:20261105T090000Z\r\nEND:VEVENT\r\n" +
                    "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261103\r\nSUMMARY:Holi\r\n day\r\nEND:VEVENT\r\n" +
                    "BEGIN:VEVENT\r\nSUMMARY:Standup\r\nDTSTART;TZID=Europe/Berlin:20261103T150000\r\nRRULE:FREQ=DAILY\r\nEND:VEVENT\r\n" +
                    "BEGIN:VEVENT\r\nSUMMARY:Past\r\nDTSTART:20261103T080000\r\nEND:VEVENT\r\n" +
                    "BEGIN:VEVENT\r\nSUMMARY:Far\r\nDTSTART:20261201T080000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        const events = Sources.icsEvents(ics);
        compare(events.length, 5);
        compare(events[0].title, "Dentist, Dr. A", "escapes undone");
        compare(events[1].title, "Holiday", "folded lines joined");
        verify(events[1].allDay);
        compare(events[0].start.getTime(), Date.UTC(2026, 10, 5, 9, 0, 0), "Z is UTC");
        const now = new Date(2026, 10, 3, 12, 0);
        const c = Sources.calendar(events, now, 7, true, en);
        fieldsMatch("calendar", c);
        compare(c.events.map(e => e.title).join("|"), "Holiday|Standup|Dentist, Dr. A", "today's all-day, then by time; past and far left out");
        compare(c.events[0].when, "Today, All day");
        compare(c.events[1].when, "Today, 15:00", "a TZID time taken as local");
        compare(c.events[2].date, "Thu, Nov 5");
        compare([c.next, c.count].join(), "Holiday,3");
        compare(Sources.calendar([], now, 7, true, en).next, "No events");
    }

    // ---- WidgetSources: only the sources a widget binds, with its options ----
    Component { id: sourcesComp; WidgetSources {} }
    function test_sources_used() {
        const spec = { version: 1, name: "x", sources: { countdown: { target: "2099-01-01" } }, root: { type: "column", children: [
            { type: "stat", label: "{{clock.weekday}}", value: "{{clock.time}}" },
            { type: "progress", value: "{{countdown.progress}}" }, { type: "chip", label: "{{todo.x}} {{countdown.text}}" }] } };
        compare(JSON.stringify(Spec.sourcesUsed(spec)), '{"clock":["weekday","time"],"countdown":["progress","text"]}',
                "unknown sources left out");
        compare(Spec.sourceFile("clock"), "sources/ClockSource.qml");
        const ws = createTemporaryObject(sourcesComp, root, { spec: spec });
        tryVerify(() => ws.values.clock && ws.values.countdown, 2000, "both sources answer");
        compare(ws.values.clock.weekday, Qt.locale().toString(new Date(), "dddd"));
        verify(ws.values.countdown.days > 20000, "the widget's own target: " + ws.values.countdown.days);
        compare(Object.keys(ws.values).sort().join(), "clock,countdown");
        // a widget that binds less: the source goes, and its value
        ws.spec = { version: 1, name: "y", root: { type: "chip", label: "{{clock.time}}" } };
        tryCompare(ws, "names", ["clock"]);
        compare(Object.keys(ws.values).join(), "clock");
        // options change: the source follows
        ws.spec = { version: 1, name: "z", sources: { countdown: { target: "2000-01-01" } },
                    root: { type: "chip", label: "{{countdown.text}}" } };
        tryVerify(() => ws.values.countdown?.done === true, 2000);
        // the clock ticks each second only while seconds are bound
        ws.spec = { version: 1, name: "s", root: { type: "chip", label: "{{clock.seconds}}" } };
        tryVerify(() => ws.values.clock !== undefined, 2000);
        const first = ws.values.clock.seconds;
        tryVerify(() => ws.values.clock.seconds !== first, 2500, "a second later, a new value");
    }
    Component {
        id: liveComp
        Item {
            property alias spec: feed.spec
            readonly property alias host: host
            WidgetSources { id: feed }
            WidgetHost { id: host; width: 360; spec: feed.spec; values: feed.values }
        }
    }
    function test_widget_filled_by_its_sources() {
        const live = createTemporaryObject(liveComp, root, { spec: readJson("../data/widgets/countdown.json") });
        // the example counts to a past Christmas or a coming one: either way a text, never the dash
        tryVerify(() => {
            const all = [];
            const walk = it => { if (it.text !== undefined && it.font !== undefined) all.push(it.text); for (const c of it.children) walk(c); };
            walk(live.host);
            return all.indexOf("Countdown") >= 0 && all.indexOf(Spec.MISSING) < 0 && all.some(t => /day|min|Now| h/.test(t));
        }, 2000, "the countdown's text filled in");
    }

    // ---- the renderer with sources ----
    Component { id: hostComp; WidgetHost { width: 360 } }
    function test_list_rows_repeat() {
        const spec = readJson("../data/widgets/list.json");
        const h = createTemporaryObject(hostComp, root, { spec: spec, values: { calendar: { events: [
            { title: "Dentist", when: "Thu, 10:00" }, { title: "Gym", when: "Fri, 18:00" }] } } });
        waitForRendering(h);
        const rows = [];
        const walk = it => { if (it.objectName === "widgetListRow") rows.push(it); for (const c of it.children) walk(c); };
        walk(h);
        compare(rows.length, 2, "one row per event");
        compare(Spec.rows(spec.root.children[0].children[1], { calendar: { events: [] } }).length, 0, "no events: no rows");
        const many = [];
        for (let i = 0; i < 20; i++) many.push({ title: "e" + i });
        compare(Spec.rows({ type: "listRow", title: "{{calendar.events.title}}" }, { calendar: { events: many } }).length,
                Spec.MAX_ROWS);
        compare(Spec.rows({ type: "listRow", title: "{{battery.level}}" }, { battery: { level: 3 } }).length, 1, "no list: one row");
        const lines = Spec.rows({ type: "listRow", title: "{{files.lines.text}}" }, { files: { lines: [{ text: "a" }, { text: "b" }] } });
        compare(lines.map(v => Spec.resolve("{{files.lines.text}}", v)).join(), "a,b");
    }
    function test_binding_problems() {
        compare(Spec.bindingProblem("battery.level"), "");
        compare(Spec.bindingProblem("battery.lvl"), 'battery has no field "lvl"');
        compare(Spec.bindingProblem("todo.x"), 'no source "todo"');
        compare(Spec.bindingProblem("calendar.events.title"), "");
        verify(Spec.bindingProblem("calendar.events.place") !== "");
        compare(Spec.bindingProblem("http.rates.EUR"), "");
        compare(Spec.bindingProblem("files.json.a.b"), "");
        verify(Spec.bindingProblem("files.json") !== "");
        verify(Spec.bindingProblem("battery.level.x") !== "");
        const p = Spec.problems({ version: 1, name: "x", root: { type: "chip", label: "{{battery.lvl}}" } });
        compare(p.join(), 'root.label: battery has no field "lvl", shows ' + Spec.MISSING);
        for (const n of ["weather", "stat-card", "countdown", "list", "stat"])
            compare(Spec.problems(readJson("../data/widgets/" + n + ".json")).join(), "", n);
    }
}
