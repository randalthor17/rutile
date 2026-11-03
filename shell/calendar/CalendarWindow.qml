// The calendar's layer-shell surface at the top left, under the clock (D93). As the notification list's (D41): the
// shell creates it in a LazyLoader only while open (D31), it takes the keyboard on opening, Escape or a click into a
// window closes it, and closing plays the panel's motion before closeRequested asks the shell to unload it. Each time
// it opens it reads the calendar folder and fetches the calendar addresses (Settings > Calendar: Google Calendar's
// secret address and the like, D94) and reads evolution-data-server's calendars (Google accounts added in GNOME
// Online Accounts, D95), and no more: nothing runs while it is closed. GNOME Calendar edits those: a click on such an
// event opens it there, and "Open Calendar" opens the app.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.services
import "Calendar.js" as Calendar

PanelWindow {
    id: root

    readonly property bool closing: !panel.shown
    readonly property alias panel: panel
    readonly property string folder: Calendar.expandHome(Settings.value("calendar.folder") ?? "", Quickshell.env("HOME"))
    property bool hasFolder: true
    property bool read: false                // the folder has been read once
    property string folderText: ""
    readonly property alias feeds: feeds
    readonly property alias eds: eds
    // GNOME Calendar, when installed (RUTILE_CALENDAR_APP replaces it, for the tests)
    readonly property string app: Quickshell.env("RUTILE_CALENDAR_APP") || "gnome-calendar"
    property bool hasApp: false

    signal closeRequested()
    signal settingsRequested()

    function close() { panel.shown = false; }
    function reopen() { panel.shown = true; }

    anchors.top: true
    anchors.left: true
    margins.top: 2 * Spacing.sm + Spacing.xl       // below the clock
    margins.left: Spacing.sm
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "rutile-calendar"
    implicitWidth: panel.width
    implicitHeight: panel.maxHeight
    mask: Region {
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
    }
    color: "transparent"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    onFolderChanged: reader.running = folder !== ""
    Component.onCompleted: reader.running = folder !== ""
    Process {
        id: reader
        command: Calendar.readCommand(root.folder)
        stdout: StdioCollector { onStreamFinished: root.folderText = text }
        onExited: code => {
            root.hasFolder = code === 0;
            root.read = true;
        }
    }

    CalendarFeeds {
        id: feeds
        addresses: Settings.value("calendar.feeds") ?? []
    }
    EdsCalendar {
        id: eds
        // the six weeks the month shows
        from: panel.days[0]
        to: new Date(panel.days[41].getFullYear(), panel.days[41].getMonth(), panel.days[41].getDate() + 1)
    }
    Process {
        running: true
        command: ["sh", "-c", 'command -v "$1"', "sh", root.app]
        onExited: code => root.hasApp = code === 0
    }
    function openApp(args) {
        Quickshell.execDetached([root.app].concat(args));
        root.close();
    }

    CalendarPanel {
        id: panel
        objectName: "calendarPanel"
        focus: true
        now: clock.date
        events: Calendar.icsEvents(root.folderText + "\n" + feeds.text).concat(Calendar.edsEvents(eds.text))
        hasFolder: (root.folder !== "" && root.hasFolder) || feeds.addresses.length > 0 || eds.available
        hasApp: root.hasApp
        onEventOpened: uuid => root.openApp(["--uuid", uuid])
        onAppRequested: root.openApp([])
        note: feeds.failed.length === 0 ? "" : feeds.failed.length === 1 ? "A calendar could not be refreshed: showing its saved events."
            : feeds.failed.length + " calendars could not be refreshed: showing their saved events."
        onSettingsRequested: root.settingsRequested()
        onWindowFocusLost: root.close()
        onHidden: root.closeRequested()
        Keys.onEscapePressed: root.close()
    }
}
