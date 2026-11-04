// The calendar source without a path (D102): the calendars the calendar under the clock shows, Settings > Calendar's
// folder and the accounts' calendars in evolution-data-server (a fake rutile-calendar), together and soonest first;
// a widget with a path of its own reads only that and never asks the data server.
// env FAKE_CALENDAR_LOG=@WS@/home/widget-calendar.log
// env FAKE_CALENDAR_EVENTS=@WS@/home/widget-events.jsonl
// env RUTILE_CALENDAR=@WS@/bin/fake-rutile-calendar
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.widgethost

ShellRoot {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string log: Quickshell.env("FAKE_CALENDAR_LOG")
    property int stage: 0
    QsTest { id: t }

    function widget(label, sources) {
        return { version: 1, name: "t", sources: sources ?? {}, root: { type: "chip", label: label } };
    }
    // tomorrow at 12:00, from the account; tomorrow, all day, from the folder; and another folder for the widget's own
    readonly property date tomorrowNoon: {
        const d = new Date();
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 12);
    }
    Process {
        id: setup
        running: true
        command: ["sh", "-c", 'mkdir -p "$1/mycal/personal" "$1/own" && ' +
                  'printf "BEGIN:VCALENDAR\\r\\nBEGIN:VEVENT\\r\\nSUMMARY:Folder thing\\r\\nDTSTART;VALUE=DATE:$2\\r\\nEND:VEVENT\\r\\nEND:VCALENDAR\\r\\n" > "$1/mycal/personal/a.ics" && ' +
                  'printf "BEGIN:VCALENDAR\\r\\nBEGIN:VEVENT\\r\\nSUMMARY:Own thing\\r\\nDTSTART;VALUE=DATE:$2\\r\\nEND:VEVENT\\r\\nEND:VCALENDAR\\r\\n" > "$1/own/b.ics" && ' +
                  'printf "%s\\n" "$4" > "$3"',
                  "sh", root.home, Qt.formatDate(root.tomorrowNoon, "yyyyMMdd"), Quickshell.env("FAKE_CALENDAR_EVENTS"),
                  JSON.stringify({ calendar: "Work", color: "", source: "google-1", uid: "ev1", rid: "", title: "Account thing",
                                   location: "", start: Math.floor(root.tomorrowNoon.getTime() / 1000),
                                   end: Math.floor(root.tomorrowNoon.getTime() / 1000) + 1800, allDay: false })]
    }
    FileView {
        id: logFile
        path: root.log
        blockLoading: true
        printErrors: false
    }

    WidgetSources {
        id: mine
        spec: root.stage >= 1 ? root.widget("{{calendar.next}}", { calendar: { days: 3 } }) : null
    }
    WidgetSources {
        id: own
        spec: root.stage >= 2 ? root.widget("{{calendar.next}}", { calendar: { path: "~/own" } }) : null
    }

    Timer {
        interval: 200
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            if (++ticks > 150) {
                t.verify(false, "timed out at stage " + root.stage + ": " + JSON.stringify(mine.values.calendar));
                t.done();
                running = false;
                return;
            }
            const c = mine.values.calendar;
            if (root.stage === 0 && !setup.running) {
                Settings.set("calendar.folder", "~/mycal");
                root.stage = 1;
            } else if (root.stage === 1 && c?.count === 2) {
                t.compare(c.events.map(e => e.title).join("|"), "Folder thing|Account thing",
                          "the folder's and the account's, the all-day one first on its day");
                t.compare(c.events[1].date, "Tomorrow");
                logFile.reload();
                // the last read: the widget's options come just after the source is made
                const last = logFile.text().split("\n").filter(l => l.startsWith("events ")).slice(-1)[0];
                const today = new Date();
                const from = Math.floor(new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime() / 1000);
                const to = Math.floor(new Date(today.getFullYear(), today.getMonth(), today.getDate() + 3).getTime() / 1000);
                t.compare(last, "events " + from + " " + to, "the data server asked for today and the days ahead");
                t.verify(logFile.text().split("\n").indexOf("sources") < 0, "a widget lists no calendars to add to");
                root.stage = 2;
            } else if (root.stage === 2 && own.values.calendar?.count === 1) {
                t.compare(own.values.calendar.next, "Own thing", "a path of its own: only that");
                logFile.reload();
                const asks = logFile.text().split("\n").filter(l => l.startsWith("events ")).length;
                t.verify(asks >= 1, "the first widget asked");
                root.stage = 3;
                ticks = 140;            // a moment for a stray read, then the count again
                root.asks = asks;
            } else if (root.stage === 3 && ticks >= 148) {
                logFile.reload();
                t.compare(logFile.text().split("\n").filter(l => l.startsWith("events ")).length, root.asks,
                          "the widget with a path of its own never asks the data server");
                t.done();
                running = false;
            }
        }
    }
    property int asks: 0
}
