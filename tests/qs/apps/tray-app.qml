// A tray app for the app indicator smoke test (plan 2.10), and to try the tray by hand (`nix run .#tray-demo`): Qt
// publishes it as a StatusNotifierItem with a DBusMenu once a tray host is on the bus. Run with `qml -a gui`. Its
// menu: an entry, a check, a submenu and Quit; each choice is printed ("chose <text>") so the test can see it
// arrived. `-- --icon-name NAME`: a theme icon by name (as most apps send theirs) instead of its own image.
import QtQuick
import Qt.labs.platform

QtObject {
    readonly property var args: Qt.application.arguments
    readonly property string iconName: args.indexOf("--icon-name") >= 0 ? args[args.indexOf("--icon-name") + 1] : ""
    property SystemTrayIcon tray: SystemTrayIcon {
        visible: true
        icon.name: iconName
        icon.source: iconName ? "" : Qt.resolvedUrl("tray-icon.png")      // a file: the sandbox has no icon theme
        tooltip: "Rutile tray test"
        onActivated: reason => console.log("activated " + reason)
        menu: Menu {
            MenuItem { text: "&Open"; onTriggered: console.log("chose Open") }
            MenuItem { text: "Muted"; checkable: true; checked: true; onTriggered: console.log("chose Muted") }
            MenuSeparator {}
            Menu {
                title: "More"
                MenuItem { text: "Inner"; onTriggered: console.log("chose Inner") }
            }
            MenuItem { text: "Quit"; onTriggered: { console.log("chose Quit"); Qt.quit(); } }
        }
    }
}
