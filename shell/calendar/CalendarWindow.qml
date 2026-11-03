// The calendar's layer-shell surface at the top left, under the clock (D93). As the notification list's (D41): the
// shell creates it in a LazyLoader only while open (D31), it takes the keyboard on opening, Escape or a click into a
// window closes it, and closing plays the panel's motion before closeRequested asks the shell to unload it. It reads
// the calendar folder (Settings > Calendar) each time it opens, and no more: nothing runs while it is closed.
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
        stdout: StdioCollector { onStreamFinished: panel.events = Calendar.icsEvents(text) }
        onExited: code => {
            root.hasFolder = code === 0;
            root.read = true;
        }
    }

    CalendarPanel {
        id: panel
        objectName: "calendarPanel"
        focus: true
        now: clock.date
        hasFolder: root.folder !== "" && root.hasFolder
        onSettingsRequested: root.settingsRequested()
        onWindowFocusLost: root.close()
        onHidden: root.closeRequested()
        Keys.onEscapePressed: root.close()
    }
}
