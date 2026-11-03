// The widget data sources that need Quickshell (plan 4.2, D79), in the shell: system from /proc, battery from the
// system's UPower (read only), media with no players (a private bus), a file and a calendar folder in the test's
// own HOME, and weather and http from a web server of the test's own on a free port. An address Settings does not
// allow is never fetched.
// env RUTILE_TEST_PORT=@PORT@
// env RUTILE_WEATHER_URL=http://127.0.0.1:@PORT@/forecast
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.widgethost

ShellRoot {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string port: Quickshell.env("RUTILE_TEST_PORT")
    readonly property string base: "http://127.0.0.1:" + port + "/"
    property int stage: 0
    QsTest { id: t }

    function widget(label, sources) {
        return { version: 1, name: "t", sources: sources ?? {}, root: { type: "chip", label: label } };
    }

    // the test's web server, and the files the sources read
    Process {
        running: true
        command: ["python3", "-m", "http.server", root.port, "--bind", "127.0.0.1", "--directory",
                  Quickshell.shellDir + "/www"]
    }
    Process {
        id: setup
        running: true
        command: ["sh", "-c", 'mkdir -p "$1/cal" && printf "first line\\nsecond\\n" > "$1/note.txt" && ' +
                  'printf "BEGIN:VCALENDAR\\r\\nBEGIN:VEVENT\\r\\nSUMMARY:Far away\\r\\nDTSTART:20991231T100000\\r\\nEND:VEVENT\\r\\nEND:VCALENDAR\\r\\n" > "$1/cal/a.ics" && ' +
                  'printf "BEGIN:VCALENDAR\\r\\nBEGIN:VEVENT\\r\\nSUMMARY:Tomorrow thing\\r\\nDTSTART;VALUE=DATE:$2\\r\\nEND:VEVENT\\r\\nEND:VCALENDAR\\r\\n" > "$1/cal/b.ics"',
                  "sh", root.home, Qt.formatDate(new Date(Date.now() + 86400000), "yyyyMMdd")]
    }
    Process {
        id: rewrite
        command: ["sh", "-c", 'printf "changed\\n" > "$1/note.txt"', "sh", root.home]
    }

    WidgetSources { id: system; spec: root.widget("{{system.cpu}} {{system.memoryTotal}} {{system.uptime}} {{system.cores}} {{system.download}}") }
    // D87: whatever this machine has; a machine without a card or sensors gets `available: false` and no fields
    WidgetSources { id: gpu; spec: root.widget("{{gpu.usage}}") }
    WidgetSources { id: sensors; spec: root.widget("{{sensors.hottest}}") }
    WidgetSources { id: battery; spec: root.widget("{{battery.level}}") }
    WidgetSources { id: media; spec: root.widget("{{media.title}}") }
    WidgetSources { id: files; spec: root.stage >= 1 ? root.widget("{{files.firstLine}}", { files: { path: "~/note.txt" } }) : null }
    WidgetSources {
        id: calendar
        spec: root.stage >= 1 ? root.widget("{{calendar.next}}", { calendar: { path: "~/cal", days: 3 } }) : null
    }
    WidgetSources { id: weather; spec: root.stage >= 1 ? root.widget("{{weather.temperature}}") : null }
    WidgetSources {
        id: http
        spec: root.stage >= 1 ? root.widget("{{http.rates.USD}}", { http: { url: root.base + "rates.json" } }) : null
    }
    WidgetSources {
        id: denied
        spec: root.stage >= 1 ? root.widget("{{http.rates.USD}}", { http: { url: "http://127.0.0.1:" + root.port + "2/x.json" } }) : null
    }

    Timer {
        interval: 500
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (root.stage === 0 && ticks >= 2 && !setup.running) {
                // a place and an allowed address, as Settings > Widgets would save them
                Settings.set("widgets.latitude", 52.52);
                Settings.set("widgets.longitude", 13.41);
                Settings.set("widgets.httpAllow", [root.base]);
                root.stage = 1;
                return;
            }
            const ready = root.stage === 1 && system.values.system?.uptime && files.values.files?.firstLine
                && calendar.values.calendar?.count > 0 && weather.values.weather?.temperature !== undefined
                && http.values.http?.rates;
            if (root.stage === 1 && (ready || ticks > 24)) {
                const s = system.values.system ?? {};
                t.verify(s.cpu >= 0 && s.cpu <= 100, "processor use in percent: " + s.cpu);
                t.verify(/GB$/.test(s.memoryTotal ?? ""), "memory: " + s.memoryTotal);
                t.verify((s.uptime ?? "") !== "", "uptime: " + s.uptime);
                t.verify(s.cores?.length > 0 && s.cores.every(c => c >= 0 && c <= 100), "cores: " + JSON.stringify(s.cores));
                t.verify(/(KB|MB)\/s$/.test(s.download ?? ""), "download: " + s.download);
                t.verify(s.cpuHistory?.length >= 1, "a history: " + JSON.stringify(s.cpuHistory));
                const g = gpu.values.gpu ?? {};
                t.verify(g.available === false || (g.usage >= 0 && g.usage <= 100 && g.vramTotal !== ""), "gpu: " + JSON.stringify(g));
                const n = sensors.values.sensors ?? {};
                t.verify(Array.isArray(n.temperatures) && n.temperatures.every(x => x.value > 0 && x.value < 150),
                         "sensors: " + JSON.stringify(n));
                const b = battery.values.battery ?? {};
                t.verify(b.present === false || (b.level >= 0 && b.level <= 100), "battery: " + JSON.stringify(b));
                t.compare(media.values.media?.playing, false, "no players on this bus");
                t.compare(files.values.files?.firstLine, "first line", "the file");
                t.compare(calendar.values.calendar?.next, "Tomorrow thing", "the folder's events, the far one left out");
                t.compare(calendar.values.calendar?.count, 1, "within 3 days");
                t.compare(weather.values.weather?.temperature, 8, "Open-Meteo's answer, from the test's server");
                t.compare(weather.values.weather?.condition, "Partly cloudy");
                t.compare(http.values.http?.rates?.USD, 1.08, "an allowed address");
                t.compare(JSON.stringify(denied.values.http ?? {}), "{}", "an address Settings does not allow: nothing");
                t.verify((denied.errors.http ?? "").indexOf("is not allowed") > 0, "and it says why: " + denied.errors.http);
                rewrite.running = true;
                root.stage = 2;
                ticks = 0;
                return;
            }
            if (root.stage === 2 && (files.values.files?.firstLine === "changed" || ticks > 8)) {
                t.compare(files.values.files?.firstLine, "changed", "the file read again when it changes");
                // no place: the weather says so and fetches nothing
                Settings.set("widgets.latitude", undefined);
                root.stage = 3;
                ticks = 0;
                return;
            }
            if (root.stage === 3 && ticks >= 2) {
                t.verify((weather.errors.weather ?? "").indexOf("no place") === 0, "no place: " + weather.errors.weather);
                t.done();
            }
        }
    }
}
