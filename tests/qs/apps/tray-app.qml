// A tray app for the app indicator smoke test (plan 2.10): Qt publishes it as a StatusNotifierItem with a DBusMenu
// once a tray host is on the bus. Run with `qml -a gui`. Its menu: an entry, a check, a submenu and Quit; each
// choice is printed ("chose <text>") so the test can see it arrived.
import QtQuick
import Qt.labs.platform

QtObject {
    property SystemTrayIcon tray: SystemTrayIcon {
        visible: true
        icon.source: Qt.resolvedUrl("tray-icon.png")      // a file: the sandbox has no icon theme
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
