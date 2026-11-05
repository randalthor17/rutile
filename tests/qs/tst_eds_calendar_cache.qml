// The evolution-data-server reader's saved copy with a fake rutile-calendar: a read is kept in `cacheFile`, and the
// next reader shows it at once while its own read is slow (an account's calendars loading), then shows what that read
// printed and keeps it instead.
// env FAKE_CALENDAR_LOG=@WS@/home/cache.log
// env FAKE_CALENDAR_EVENTS=@WS@/home/cache-events.jsonl
import QtQuick
import Quickshell
import Quickshell.Io
import qs.calendar
import "calendar/Calendar.js" as Calendar

ShellRoot {
    id: root
    readonly property string log: Quickshell.env("FAKE_CALENDAR_LOG")
    readonly property string events: Quickshell.env("FAKE_CALENDAR_EVENTS")
    readonly property string cacheFile: Quickshell.env("HOME") + "/saved/accounts.jsonl"
    readonly property string first: '{"source":"g","uid":"a","title":"First","start":1793761200,"end":1793763000}'
    readonly property string second: '{"source":"g","uid":"b","title":"Second","start":1793761200,"end":1793763000}'
    property int stage: 0
    QsTest { id: t }

    Process {
        id: sh
        command: ["sh", "-c", ""]
    }
    function run(script) {
        sh.command = ["sh", "-c", script, "sh", root.log, root.events, root.cacheFile, root.first, root.second];
        sh.running = true;
    }
    Process {
        id: readCache
        command: ["cat", root.cacheFile]
        stdout: StdioCollector { id: cached }
    }
    Component.onCompleted: run('mkdir -p "$(dirname "$1")" && rm -f "$3" "$1.slow" && printf "%s\\n" "$4" > "$2"')

    Loader {
        id: eds
        active: root.stage === 1 || root.stage === 3
        sourceComponent: EdsCalendar {
            helper: Quickshell.shellDir + "/bin/fake-rutile-calendar"
            cacheFile: root.cacheFile
            listCalendars: false
            from: new Date(1793700000 * 1000)
            to: new Date(1794000000 * 1000)
        }
    }

    function titles(text) {
        return Calendar.edsEvents(text).map(e => e.title).join();
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        property int ticks: 0
        property int mark: 0
        onTriggered: {
            ticks++;
            if (ticks > 150) {
                t.verify(false, "timed out at stage " + root.stage);
                t.done();
                running = false;
                return;
            }
            const e = eds.item;
            if (root.stage === 0 && !sh.running && ticks > 2) {
                root.stage = 1;
            } else if (root.stage === 1 && e && e.done && e.synced && !e.again && ticks > mark + 5) {
                t.compare(titles(e.text), "First", "the first reader's events");
                readCache.running = true;
                root.stage = 10;
            } else if (root.stage === 10 && !readCache.running) {
                t.compare(titles(cached.text), "First", "kept in the cache file");
                // the next read is slow and prints another event
                root.run('touch "$1.slow" && printf "%s\\n" "$5" > "$2"');
                root.stage = 2;
            } else if (root.stage === 2 && !sh.running) {
                root.stage = 3;
                mark = ticks;
            } else if (root.stage === 3 && e && ticks === mark + 8) {
                t.verify(!e.done, "its read still running");
                t.compare(titles(e.text), "First", "meanwhile, what the last read printed");
            } else if (root.stage === 3 && e && e.done && ticks > mark + 25) {
                t.compare(titles(e.text), "Second", "then what its own read printed");
                readCache.running = true;
                root.stage = 30;
            } else if (root.stage === 30 && !readCache.running) {
                t.compare(titles(cached.text), "Second", "kept instead");
                t.done();
                running = false;
            }
        }
    }
}
