// The settings app's window (plan 5.1): an ordinary app window (xdg toplevel) that the compositor places and
// decorates like any other, in the shell's process so it shares the Settings service, the palette and the fonts.
// The shell creates it only while it is open (D31): closing it (its close button, or niri's close-window)
// unloads it. A path setting is chosen with Qt's FileDialog, which the shell routes to the desktop portal (D51),
// so it is the user's own file chooser.
import QtQuick
import QtQuick.Dialogs
import Quickshell
import qs.common
import qs.services

FloatingWindow {
    id: root

    readonly property alias app: app
    readonly property alias fileDialog: fileDialog

    signal finished()

    title: "Settings"
    implicitWidth: 1100
    implicitHeight: 760
    minimumSize: Qt.size(400, 480)
    color: Colors.surfaceContainerLow
    onClosed: root.finished()

    SettingsApp {
        id: app
        anchors.fill: parent
        store: Settings
        focus: true
        onPathRequested: (key, filters) => {
            const current = Settings.value(key) ?? "";
            fileDialog.key = key;
            fileDialog.nameFilters = filters.length ? filters : ["All files (*)"];
            if (current !== "")
                fileDialog.currentFolder = "file://" + current.substring(0, current.lastIndexOf("/"));
            fileDialog.open();
        }
    }

    FileDialog {
        id: fileDialog
        property string key: ""
        title: "Choose a file"
        parentWindow: app.Window.window
        onAccepted: {
            const url = selectedFile.toString();
            if (url.startsWith("file://")) Settings.set(key, decodeURIComponent(url.substring(7)));
        }
    }
}
