pragma ComponentBehavior: Bound
// What the greeter shows on each screen (plan 6.2, D97): the lock screen's face (LockPanel: the time, the person's
// name, the field greetd's questions are answered in, over the blurred wallpaper), and along the bottom, as on
// ChromeOS's sign-in screen, Shut down and Restart, who signs in (a menu when there are several) and into which
// session (always shown, a menu). Plain QtQuick: greeter.qml gives it the people, sessions, greetd's state and the motion, so it tests
// offscreen.
import QtQuick
import qs.common
import qs.components
import qs.lock
import "Greeter.js" as Greeter

Item {
    id: root

    required property date now
    property var users: []                  // Greeter.users
    property string user: ""
    property var sessions: []               // Greeter.sessions
    property string session: ""             // its id
    property string prompt: ""              // greetd's question
    property bool secret: true
    property bool busy: false
    property string error: ""
    property string info: ""
    property string wallpaper: ""
    property real progress: 1

    readonly property var userEntry: users.find(u => u.name === user) ?? null
    readonly property var sessionEntry: sessions.find(s => s.id === session) ?? null
    readonly property var promptText: Greeter.promptText(prompt, secret)
    readonly property alias face: face

    signal submitted(string text)
    signal edited()
    signal userChosen(string name)
    signal sessionChosen(string id)
    signal powerRequested(string action)    // poweroff | reboot

    LockPanel {
        id: face
        anchors.fill: parent
        now: root.now
        user: root.userEntry?.realName ?? root.user
        busy: root.busy
        error: root.error
        message: root.promptText.message !== "" ? root.promptText.message : root.info
        secret: root.secret
        placeholder: root.promptText.placeholder
        wallpaper: root.wallpaper
        progress: root.progress
        onSubmitted: text => root.submitted(text)
        onEdited: root.edited()
    }

    Row {
        id: bar
        objectName: "greeterBar"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Spacing.lg
        spacing: Spacing.sm
        opacity: face.shown

        Button {
            objectName: "greeterPoweroff"
            type: "tonal"
            iconName: "power_settings_new"
            text: "Shut down"
            onClicked: root.powerRequested("poweroff")
        }
        Button {
            objectName: "greeterReboot"
            type: "tonal"
            iconName: "restart_alt"
            text: "Restart"
            onClicked: root.powerRequested("reboot")
        }
        Button {
            id: userButton
            objectName: "greeterUser"
            visible: root.users.length > 1
            type: "tonal"
            iconName: "person"
            text: root.userEntry?.realName ?? root.user
            onClicked: userMenu.open = !userMenu.open
        }
        Button {
            id: sessionButton
            objectName: "greeterSession"
            visible: root.sessions.length > 0
            type: "tonal"
            iconName: "desktop_windows"
            text: root.sessionEntry?.name ?? root.session
            onClicked: sessionMenu.open = !sessionMenu.open
        }
    }

    PopupLoader {
        id: userMenu
        origin: Item.Bottom
        x: bar.x + userButton.x
        y: bar.y - ((item as Item)?.height ?? 0) - Spacing.sm
        sourceComponent: Menu {
            itemPrefix: "greeterUser_"
            items: root.users.map(u => ({ id: u.name, text: u.realName, icon: "person", check: "radio",
                                          checked: u.name === root.user }))
            onChosen: id => {
                userMenu.open = false;
                root.userChosen(id);
            }
        }
    }
    PopupLoader {
        id: sessionMenu
        origin: Item.Bottom
        x: bar.x + sessionButton.x
        y: bar.y - ((item as Item)?.height ?? 0) - Spacing.sm
        sourceComponent: Menu {
            itemPrefix: "greeterSession_"
            items: root.sessions.map(s => ({ id: s.id, text: s.name, icon: "desktop_windows", check: "radio",
                                             checked: s.id === root.session }))
            onChosen: id => {
                sessionMenu.open = false;
                root.sessionChosen(id);
            }
        }
    }
}
