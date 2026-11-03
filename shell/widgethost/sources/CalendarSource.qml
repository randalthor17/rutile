// The calendar source (plan 4.2, D79): an .ics file, or every .ics file in a folder (vdirsyncer keeps one event per
// file), read every 5 minutes; the upcoming events worked out again at every minute.
import QtQuick
import qs.widgethost
import Quickshell
import Quickshell.Io
import "../Sources.js" as Sources
import "../../bar/ClockText.js" as ClockText

WidgetSource {
    id: root
    value: Sources.calendar([], new Date(), 7, true, Qt.locale())
    property var events: []
    readonly property string path: {
        const p = options.path ?? "";
        return p.startsWith("~/") ? Quickshell.env("HOME") + p.substring(1) : p;
    }
    readonly property bool use24h: ClockText.uses24h(Qt.locale().timeFormat(Locale.ShortFormat))

    function update() {
        value = Sources.calendar(events, new Date(), options.days ?? 7, use24h, Qt.locale());
    }
    onEventsChanged: update()
    onPathChanged: read.running = path !== ""
    Process {
        id: read
        command: ["sh", "-c", 'if [ -d "$1" ]; then cat "$1"/*.ics 2>/dev/null; else cat "$1"; fi', "sh", root.path]
        stdout: StdioCollector { onStreamFinished: root.events = Sources.icsEvents(text) }
    }
    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: root.path !== ""
        triggeredOnStart: true
        onTriggered: read.running = true
    }
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.update()
    }
}
