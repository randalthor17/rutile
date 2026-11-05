// The user's calendars in evolution-data-server (D95): Google and other accounts added in GNOME Online Accounts, and
// local ones, as GNOME Calendar shows and edits them. `helper` (rutile-calendar, native/calendar.c) prints the
// events on between `from` and `to`; when this is created it reads them, asks the calendars to sync with their
// servers, then reads them again. A new range reads again (once more if one was asked for while reading, so the
// last range wins). `available` is false while evolution-data-server cannot be reached or the helper is missing.
// `calendars` are the ones an event can be added to; `add()` adds one (D101), then reads again; `added` says how it
// went.
import QtQuick
import Quickshell
import Quickshell.Io
import "Calendar.js" as Calendar

Scope {
    id: root

    property string helper: Calendar.helperPath(Quickshell.env("RUTILE_CALENDAR"), Quickshell.shellDir)
    property date from: new Date()
    property date to: new Date()
    property string text: ""                // the helper's lines
    property bool available: false
    property bool done: false               // read once
    property bool synced: false             // the sync has been asked for
    property bool again: false
    property var calendars: []              // Calendar.edsCalendars
    property bool listCalendars: true       // read `calendars` (the popup adds events to them; a widget does not)
    property bool adding: false
    signal added(bool ok, string error)

    function add(source, allDay, start, end, title) {
        if (adding) return false;
        adding = true;                       // at once: `running` turns true only once it has started
        adder.command = Calendar.addCommand(root.helper, source, allDay, start, end, title);
        adder.running = true;
        return true;
    }

    function read() {
        if (reader.running) again = true;
        else reader.running = true;
    }
    // later: the command's binding has not taken the new range yet, and a new month changes both ends at once
    onFromChanged: if (done) Qt.callLater(read)
    onToChanged: if (done) Qt.callLater(read)
    Component.onCompleted: read()

    Process {
        id: reader
        command: Calendar.edsCommand(root.helper, root.from, root.to)
        stdout: StdioCollector { id: lines }
        onExited: code => {
            root.available = code === 0;
            if (code === 0) root.text = lines.text;
            root.done = true;
            if (root.again) {
                root.again = false;
                reader.running = true;
            } else if (code === 0 && !root.synced) {
                root.synced = true;
                sync.running = true;
                lister.running = root.listCalendars;
            }
        }
    }
    // the calendars sync with their servers (Google's), then the events are read again
    Process {
        id: sync
        command: [root.helper, "refresh"]
        onExited: root.read()
    }
    Process {
        id: lister
        command: [root.helper, "sources"]
        stdout: StdioCollector { onStreamFinished: root.calendars = Calendar.edsCalendars(text) }
    }
    Process {
        id: adder
        stderr: StdioCollector { id: addErrors }
        onExited: code => {
            root.adding = false;
            const why = addErrors.text.trim().replace(/^rutile-calendar: /, "");
            if (code !== 0) console.warn("calendar: adding an event failed:", why);
            root.added(code === 0, code === 0 ? "" : why || "The event could not be added");
            if (code === 0) root.read();
        }
    }
}
