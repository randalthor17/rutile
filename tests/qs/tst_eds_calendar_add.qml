// Adding an event to an evolution-data-server calendar (D101) with a fake rutile-calendar: the calendars an event can
// go to (the default first, Birthdays left out), an event added with its times in Unix seconds and the events read
// again, and a calendar that will not take it reported.
// env FAKE_CALENDAR_LOG=@WS@/home/add.log
// env FAKE_CALENDAR_EVENTS=@WS@/home/add-events.jsonl
import QtQuick
import Quickshell
import Quickshell.Io
import qs.calendar

ShellRoot {
    id: root
    readonly property string log: Quickshell.env("FAKE_CALENDAR_LOG")
    property int stage: 0
    property var results: []
    QsTest { id: t }

    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1.sources"', "sh", root.log,
                  ['{"source":"birthdays","name":"Birthdays","color":"","backend":"contacts","selected":true,"default":false}',
                   '{"source":"google-1","name":"Work","color":"#ff0000","backend":"caldav","selected":true,"default":false}',
                   '{"source":"system-calendar","name":"Personal","color":"","backend":"local","selected":true,"default":true}'].join("\n")]
        onExited: root.stage = 1
    }
    FileView {
        id: logFile
        path: root.log
        blockLoading: true
        printErrors: false
    }
    function lines() {
        logFile.reload();
        return logFile.text().split("\n").filter(l => l);
    }

    Loader {
        id: eds
        active: root.stage >= 1
        sourceComponent: EdsCalendar {
            helper: Quickshell.shellDir + "/bin/fake-rutile-calendar"
            from: new Date(1793700000 * 1000)
            to: new Date(1794000000 * 1000)
            onAdded: (ok, error) => root.results = root.results.concat([[ok, error]])
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            if (++ticks > 150) {
                t.verify(false, "timed out at stage " + root.stage);
                t.done();
                running = false;
                return;
            }
            const e = eds.item;
            if (root.stage === 1 && e && e.calendars.length > 0) {
                t.compare(e.calendars.map(c => c.source).join(), "system-calendar,google-1",
                          "the default first; Birthdays (from contacts) cannot take events");
                t.compare(e.calendars[1].name, "Work");
                t.verify(e.add("google-1", false, new Date(1793800000 * 1000), new Date(1793803600 * 1000), "Dentist; 2"));
                t.verify(e.adding, "adding");
                t.verify(!e.add("google-1", true, new Date(0), new Date(86400000), "Another"), "one at a time");
                root.stage = 2;
            } else if (root.stage === 2 && root.results.length === 1 && !e.adding) {
                t.compare(JSON.stringify(root.results[0]), '[true,""]', "added");
                root.stage = 3;
            } else if (root.stage === 3 && root.lines().some(l => l === "add google-1 timed 1793800000 1793803600 Dentist; 2")
                       && root.lines().slice(-1)[0].startsWith("events")) {
                t.verify(true, "the event's times in seconds, the title as one argument; then the events read again");
                e.add("google-1", true, new Date(1793750400 * 1000), new Date(1793836800 * 1000), "fail");
                root.stage = 4;
            } else if (root.stage === 4 && root.results.length === 2 && root.lines().some(l => l.startsWith("add google-1 allday"))) {
                t.compare(JSON.stringify(root.results[1]), '[false,"google-1 is read-only"]', "why it was not added");
                t.verify(root.lines().some(l => l === "add google-1 allday 1793750400 1793836800 fail"), "all day");
                t.done();
                running = false;
            }
        }
    }
}
