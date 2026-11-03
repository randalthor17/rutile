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
        // what SystemSource's script prints (D87): /proc/stat, meminfo, uptime, loadavg, net/dev, df -P -B1 /, freqs
        const proc = (n, core, rx, tx) => "cpu  " + n.join(" ") + "\ncpu0 " + core.join(" ") + "\nMemTotal:       16303112 kB\n" +
            "MemFree:         1000000 kB\nMemAvailable:   10781884 kB\nSwapTotal:       8388604 kB\nSwapFree:        6291452 kB\n" +
            "11523.45 80000.12\n0.52 0.48 0.40 2/1234 5678\n" +
            "Inter-|   Receive                                                |  Transmit\n" +
            " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n" +
            "    lo: " + (rx * 3) + "   28935    0    0    0     0          0         0 " + (tx * 3) + "   28935    0    0    0     0       0          0\n" +
            "enp8s0: " + rx + " 7967539    0   54    0     0          0      9857 " + tx + " 2171498    0    0    0     0       0          0\n" +
            "Filesystem         1-blocks        Used   Available Capacity Mounted on\n" +
            "/dev/nvme0n1p2 116489654272 99924738048 10598969344      91% /\nfreq 4201676\nfreq 3600000\n";
        const p = n => proc(n, [10, 0, 10, 80, 0, 0, 0, 0], 1000000, 50000);
        const a = Sources.procSample(p([100, 0, 50, 800, 50, 0, 0, 0, 0, 0]));
        const b = Sources.procSample(proc([160, 0, 70, 900, 70, 0, 0, 0, 10, 0], [40, 0, 20, 140, 0, 0, 0, 0], 3097152, 1098576));
        compare(a.cpu.total, 1000, "guest is already in user: not counted twice");
        const s = Sources.system(a, b, 2, { cpuHistory: [1, 2] }, {}, "AMD Ryzen 5 7600");
        fieldsMatch("system", s);
        // 200 ticks passed, 120 of them idle or waiting: 40 % busy
        compare(s.cpu, 40);
        fuzzyCompare(s.cpuFraction, 0.4, 1e-9);
        compare(s.memory, 34);
        compare(s.memoryUsed, "5.3 GB");
        compare(s.memoryTotal, "16 GB");
        compare(s.uptime, "3 h 12 min");
        compare(s.load, "0.52");
        compare(s.cores, [40], "a core: 100 more ticks, 60 of them idle");
        compare(s.cpuName, "AMD Ryzen 5 7600");
        compare(Sources.cpuName("processor\t: 0\nvendor_id\t: AuthenticAMD\nmodel name\t: AMD Ryzen 5 7600 6-Core Processor\n"), "AMD Ryzen 5 7600");
        compare(Sources.cpuName("model name\t: Intel(R) Core(TM) i7-12700K CPU @ 3.60GHz\n"), "Intel Core i7-12700K");
        compare(Sources.cpuName("model name\t: AMD Ryzen 7 7840U w/ Radeon 780M Graphics\n"), "AMD Ryzen 7 7840U w/ Radeon 780M Graphics");
        compare(Sources.cpuName("processor\t: 0\nHardware\t: BCM2835\n"), "BCM2835", "ARM");
        compare(Sources.cpuName(""), "");
        compare(s.cpuFrequency, "4.2 GHz", "the fastest core");
        compare(s.cpuHistory, [1, 2, 40], "the history grows");
        compare([s.memoryUsedGB, s.memoryFreeGB], [5.3, 10.3]);
        compare([s.swap, s.swapUsed, s.swapTotal].join(), "25,2 GB,8 GB");
        compare([s.disk, s.diskUsed, s.diskFree, s.diskTotal].join(), "90,93 GB,9.9 GB,108 GB", "used of used and free, as df");
        compare([s.download, s.upload, s.downloadRate, s.uploadRate].join(), "1 MB/s,512 KB/s,1024,512",
                "2 MB and 1 MB in 2 s, loopback left out");
        compare(Sources.system(null, b, 0, null, {}).cpu, 0, "one sample: no processor use yet");
        compare(Sources.system(null, b, 0, null, {}).downloadRate, 0, "nor a rate");
        let h = null;
        for (let i = 0; i < 40; i++) h = Sources.system(a, b, 2, h, { history: 5 });
        compare(h.cpuHistory.length, 5, "a history keeps `history` samples");
        compare(Sources.historyLength({}), 60, "a minute at one reading a second");
        compare(Sources.historyLength({ history: 1000 }), 60, "out of range: the default");
        compare(Sources.pollInterval({}), 1000, "every second");
        compare(Sources.pollInterval({ every: 0.5 }), 500);
        compare(Sources.pollInterval({ every: 0.1 }), 1000, "too often: the default");
        compare(Sources.rate(500 * 1024 * 1024), "500 MB/s");
    }

    // D87: the cards' sysfs as GpuSource's script prints it (this maintainer's iGPU and RX 9060 XT), nvidia-smi's line
    function test_gpu() {
        const text = "card card0\nvendor 0x1002\ngpu_busy_percent 0\nmem_info_vram_total 536870912\nmem_info_vram_used 22933504\n" +
            "sclk 1: 600Mhz *\ntemp1_input 41000 edge\npower1_input 35091000 PPT\n" +
            "card card1\nvendor 0x1002\ngpu_busy_percent 4\nmem_info_vram_total 17095983104\nmem_info_vram_used 569626624\n" +
            "sclk 1: 2617Mhz *\ntemp1_input 43000 edge\ntemp2_input 45000 junction\ntemp3_input 60000 mem\n" +
            "power1_average 17000000 PPT\npower1_input 99000000 PPT\nfan1_input 0 \n";
        const cards = Sources.gpuSample(text);
        compare(cards.map(c => c.name).join(), "card0,card1");
        const names = Sources.gpuNames("name card0 1002:164e AMD Radeon 610M\nname card1 1002:7590 AMD Radeon RX 9060 XT\n");
        const g = Sources.gpu(cards, {}, null, null, 0, names);
        fieldsMatch("gpu", g);
        compare(g.name, "AMD Radeon RX 9060 XT", "the one with the most video memory, by its name");
        compare(Sources.gpu(cards, {}, null).name, "AMD card1", "no names: vendor and card");
        compare(JSON.stringify(Sources.gpuNames("name card0 8086:a780 pci Raptor Lake-S GT1 [UHD Graphics 770]\n" +
                                                "name card1 10de:2786 pci AD104 [GeForce RTX 4070]\nname card2 1af4:1050 \n" +
                                                "name card3 1002:73bf pci Navi 21\n")),
                JSON.stringify({ card0: "Intel UHD Graphics 770", card1: "NVIDIA GeForce RTX 4070", card2: "1af4 1af4:1050", card3: "AMD Navi 21" }),
                "pci.ids: the bracket after the vendor; none: the PCI id");
        compare([g.usage, g.vram, g.vramUsed, g.vramTotal, g.vramUsedGB, g.vramFreeGB].join(), "4,3,0.5 GB,16 GB,0.5,15.4");
        compare([g.temperature, g.hotspot, g.memoryTemperature, g.power, g.fan, g.clock].join(), "43,45,60,17,0,2.62 GHz", "the average power, not the instant one, when there are both");
        compare(g.usageHistory, [4]);
        const i = Sources.gpu(cards, { card: "card0" }, null, null, 0, names);
        compare([i.name, i.power, i.hotspot === undefined, i.fan === undefined].join(), "AMD Radeon 610M,35,true,true",
                "the card named; power1_input when there is no average; what it lacks is missing");
        compare(Sources.gpu(cards, { card: "card0" }, null).clock, "600 MHz", "under 1 GHz: in MHz");
        compare(Sources.gpu(cards, { card: "card7" }, null).available, false);
        compare(Sources.gpu([], {}, null).available, false);
        const nv = Sources.gpu(Sources.gpuSample("nvidia 37, 2048, 8192, 55, 120.5, 40, 1800, NVIDIA GeForce RTX 4070, Ti\n"), {}, null);
        compare([nv.name, nv.usage, nv.vram, nv.temperature, nv.power, nv.fan, nv.clock].join("|"),
                "NVIDIA GeForce RTX 4070, Ti|37|25|55|121|40|1.80 GHz", "nvidia-smi names it (a comma in a name is kept)");
        // Intel (i915 integrated, xe discrete): no use, a clock, a discrete card's temperature and energy counter
        const intel = t => "card card0\nvendor 0x8086\ndriver i915\ngtfreq 350\n" +
                           "card card1\nvendor 0x8086\ndriver xe\ngtfreq 2050\ntemp1_input 51000 pkg\nenergy1_input " + t + " \n";
        const before = Sources.gpuSample(intel(1000000)), after = Sources.gpuSample(intel(91000000));
        const xe = Sources.gpu(after, { card: "card1" }, null, before, 2, {});
        compare([xe.available, xe.usage === undefined, xe.vram === undefined, xe.clock, xe.temperature, xe.power].join(),
                "true,true,true,2.05 GHz,51,45", "no use or video memory; 90 J in 2 s: 45 W");
        const igpu = Sources.gpu(after, { card: "card0" }, null, before, 2, {});
        compare([igpu.clock, igpu.power === undefined, igpu.temperature === undefined].join(), "350 MHz,true,true");
        compare(Sources.gpu(after, {}, null, before, 2, {}).name, "Intel card0", "no video memory anywhere: the first card");
        // nouveau: what its hwmon gives
        const nouveau = Sources.gpu(Sources.gpuSample("card card0\nvendor 0x10de\ndriver nouveau\ntemp1_input 48000 \npower1_input 31000000 \n"), {}, null);
        compare([nouveau.temperature, nouveau.power, nouveau.usage === undefined].join(), "48,31,true");
    }
    function test_sensors() {
        const text = "hwmon nvme\ntemp1_input 44850 Composite\nhwmon k10temp\ntemp1_input 46000 Tctl\ntemp3_input 37625 Tccd1\n" +
            "hwmon gigabyte_wmi\ntemp1_input 33000 \ntemp4_input -55000 \nhwmon amdgpu\ntemp1_input 43000 edge\nrapl 1000000\n";
        const a = Sources.sensorsSample(text);
        const b = Sources.sensorsSample(text.replace("rapl 1000000", "rapl 31000000"));
        const s = Sources.sensors(a, b, 2, null, {});
        fieldsMatch("sensors", s);
        compare([s.cpu, s.nvme, s.hottest, s.cpuPower].join(), "46,45,46,15", "30 J in 2 s: 15 W");
        compare(s.temperatures.map(t => t.name + "=" + t.value).join(), "nvme Composite=45,k10temp Tctl=46,k10temp Tccd1=38,gigabyte_wmi temp1=33,amdgpu edge=43",
                "every plausible sensor, unlabelled ones by their file; -55 is no sensor");
        const noRapl = Sources.sensors(null, Sources.sensorsSample("hwmon coretemp\ntemp1_input 51000 Package id 0\n"), 0, null, {});
        compare([noRapl.cpu, noRapl.cpuPower, noRapl.nvme].join(), "51,,", "Intel's package; no power without RAPL");
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
