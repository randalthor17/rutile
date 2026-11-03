// The calendar's evolution-data-server reader (D95) with a fake rutile-calendar: it reads the events, asks for a
// sync, reads again; a new range reads that range; a data server that cannot be reached, or no helper at all, makes
// it unavailable.
// env FAKE_CALENDAR_LOG=@WS@/home/calendar.log
// env FAKE_CALENDAR_EVENTS=@WS@/home/events.jsonl
import QtQuick
import Quickshell
import Quickshell.Io
import qs.calendar
import "calendar/Calendar.js" as Calendar

ShellRoot {
    id: root
    readonly property string log: Quickshell.env("FAKE_CALENDAR_LOG")
    property int stage: 0
    QsTest { id: t }

    Process {
        id: setup
        running: true
        command: ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$3" > "$2"', "sh", root.log,
                  Quickshell.env("FAKE_CALENDAR_EVENTS"),
                  '{"calendar":"Work","color":"#ff0000","source":"google-1","uid":"ev1","rid":"","title":"Standup","location":"","start":1793761200,"end":1793763000,"allDay":false}']
        onExited: root.stage = 1
    }
    Process {
        id: readLog
        command: ["cat", root.log]
        stdout: StdioCollector { id: logText }
    }
    Process {
        id: down
        command: ["touch", root.log + ".down"]
    }

    Loader {
        id: eds
        active: root.stage >= 1 && root.stage < 4
        sourceComponent: EdsCalendar {
            helper: Quickshell.shellDir + "/bin/fake-rutile-calendar"
            from: new Date(1793700000 * 1000)
            to: new Date(1794000000 * 1000)
        }
    }
    Loader {
        id: missing
        active: root.stage === 5
        sourceComponent: EdsCalendar { helper: Quickshell.shellDir + "/bin/no-such-helper" }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        property int ticks: 0
        property int mark: 0
        onTriggered: {
            ticks++;
            if (ticks > 100) {
                t.verify(false, "timed out at stage " + root.stage);
                t.done();
                running = false;
                return;
            }
            const e = eds.item;
            if (root.stage === 1 && e && e.synced && !e.again && e.done && e.available) {
                root.stage = 2;
                mark = ticks;
            } else if (root.stage === 2 && ticks > mark + 5) {
                // the read after the sync has come back
                const events = Calendar.edsEvents(e.text);
                t.compare(events.length, 1, "one event");
                t.compare(events[0].title, "Standup", "its title");
                t.compare(events[0].start.getTime(), 1793761200000, "its start");
                t.compare(Calendar.eventUuid(events[0]), "google-1:ev1", "GNOME Calendar's id for it");
                // a new month moves both ends: one read
                e.from = new Date(1795000000 * 1000);
                e.to = new Date(1796000000 * 1000);
                root.stage = 3;
                mark = ticks;
            } else if (root.stage === 3 && ticks > mark + 5) {
                readLog.running = true;
                root.stage = 30;
            } else if (root.stage === 30 && !readLog.running && logText.text !== "") {
                t.compare(logText.text.trim().split("\n").join("|"),
                          "events 1793700000 1794000000|refresh|events 1793700000 1794000000|events 1795000000 1796000000",
                          "read, sync, read, then the new range once");
                down.running = true;
                root.stage = 4;     // drops the first one
                mark = ticks;
            } else if (root.stage === 4 && !down.running && ticks > mark + 2) {
                root.stage = 40;
            } else if (root.stage === 40) {
                root.stage = 41;
            } else if (root.stage === 41) {
                root.stage = 1;     // a new one, with the data server down
                downCheck.start();
            } else if (root.stage === 5 && missing.item && ticks > mark + 10) {
                t.verify(!missing.item.available, "no helper: unavailable");
                t.done();
                running = false;
            }
        }
    }
    Timer {
        id: downCheck
        interval: 1000
        onTriggered: {
            t.verify(!eds.item.available, "the data server down: unavailable");
            t.verify(!eds.item.synced, "no sync asked of a data server that is not there");
            t.compare(eds.item.text, "", "no events");
            root.stage = 5;
        }
    }
}
