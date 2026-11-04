// The calendar source (plan 4.2, D79): the upcoming events, repeating ones included (D93), worked out again at every
// minute. With a `path`: that .ics file, or every .ics file in that folder and the folders in it (vdirsyncer keeps
// one folder per calendar, one event per file), read every 5 minutes. Without one (D102): the calendars the calendar
// under the clock shows, Settings > Calendar's folder and addresses and the accounts' calendars in
// evolution-data-server (Google through GNOME Online Accounts), read every 5 minutes, the addresses fetched every
// 30 (their saved copies show until then).
import QtQuick
import qs.widgethost
import qs.services
import Quickshell
import Quickshell.Io
import "../Sources.js" as Sources
import "../../bar/ClockText.js" as ClockText
import "../../calendar/Calendar.js" as Calendar

WidgetSource {
    id: root
    value: Sources.calendar([], new Date(), 7, true, Qt.locale())
    readonly property bool own: (options.path ?? "") !== ""        // a path of its own, else the user's calendars
    readonly property string path: own ? Calendar.expandHome(options.path, Quickshell.env("HOME"))
                                       : Calendar.expandHome(Settings.value("calendar.folder") ?? "", Quickshell.env("HOME"))
    readonly property int days: options.days ?? 7
    property string folderText: ""
    readonly property var events: Sources.icsEvents(folderText + "\n" + (feeds.item?.text ?? ""))
                                  .concat(Calendar.edsEvents(eds.item?.text ?? ""))
    readonly property bool use24h: ClockText.uses24h(Qt.locale().timeFormat(Locale.ShortFormat))
    property date today: Calendar.startOfDay(new Date())
    readonly property date end: new Date(today.getFullYear(), today.getMonth(), today.getDate() + days)

    function update() {
        value = Sources.calendar(events, new Date(), days, use24h, Qt.locale());
    }
    onEventsChanged: update()
    onPathChanged: {
        folderText = "";
        read.running = path !== "";
    }
    Process {
        id: read
        command: Calendar.readCommand(root.path)
        stdout: StdioCollector { onStreamFinished: root.folderText = text }
    }
    // The user's calendars: only when the widget has no path of its own (D31). The popup's readers, by their files:
    // `import qs.calendar` here would need every root that shows widgets to import it too (Quickshell makes only the
    // qs modules something imports).
    Loader {
        id: feeds
        active: !root.own && (Settings.value("calendar.feeds") ?? []).length > 0
        Component.onCompleted: setSource(Qt.resolvedUrl("../../calendar/CalendarFeeds.qml"),
                                         { addresses: Settings.value("calendar.feeds") ?? [] })
        onLoaded: item.addresses = Qt.binding(() => Settings.value("calendar.feeds") ?? [])
    }
    Loader {
        id: eds
        active: !root.own
        Component.onCompleted: setSource(Qt.resolvedUrl("../../calendar/EdsCalendar.qml"),
                                         { listCalendars: false, from: root.today, to: root.end })
        onLoaded: {
            item.from = Qt.binding(() => root.today);
            item.to = Qt.binding(() => root.end);
        }
    }
    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.path !== "") read.running = true;
            if (eds.item?.done) eds.item.read();
        }
    }
    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: feeds.active
        onTriggered: feeds.item?.refresh()
    }
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            root.today = Calendar.startOfDay(new Date());
            root.update();
        }
    }
}
