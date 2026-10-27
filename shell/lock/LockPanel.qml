// What the lock screen shows on each screen (plan 2.8): the time and date large in the middle, the user's name and a
// password field under them, on the surface color (no wallpaper, so nothing of the session shows through). Enter
// sends the password (`submitted`); while `busy` the field takes no typing; `error` shows under the field and the
// field shakes. Plain QtQuick, so it tests offscreen: LockScreen gives it the time, the user and the state.
import QtQuick
import qs.common
import qs.components
import "../bar/ClockText.js" as ClockText

Rectangle {
    id: root

    required property date now
    property string user: ""
    property bool busy: false
    property string error: ""
    property string message: ""          // what PAM asks or tells, when it is not just the password
    property bool use24h: ClockText.uses24h(Qt.locale().timeFormat(Locale.ShortFormat))

    readonly property alias field: passwordInput
    readonly property string timeText: ClockText.time(now, use24h)
    readonly property string dateText: ClockText.date(now, Qt.locale())

    signal submitted(string password)
    signal edited()                      // typing after an error: the owner clears it

    function submit() {
        if (busy || passwordInput.text === "") return;
        const password = passwordInput.text;
        passwordInput.text = "";          // never kept in the item longer than needed
        submitted(password);
    }

    color: Colors.surface

    // A wrong password shakes the field.
    onErrorChanged: if (error !== "") shake.restart()
    property real shakeOffset: 0
    SequentialAnimation {
        id: shake
        // motion-speed: each step's duration is Motion.duration()
        NumberAnimation { target: root; property: "shakeOffset"; to: Spacing.md; duration: Motion.duration(Motion.short2) } // motion-speed: Motion.duration
        NumberAnimation { target: root; property: "shakeOffset"; to: -Spacing.md; duration: Motion.duration(Motion.short3) } // motion-speed: Motion.duration
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: Motion.duration(Motion.short2) } // motion-speed: Motion.duration
    }

    Column {
        anchors.centerIn: parent
        spacing: Spacing.lg

        Text {
            objectName: "lockTime"
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText
            color: Colors.surfaceOn
            font: Type.font(Type.displayLarge)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            color: Colors.surfaceVariantOn
            font: Type.font(Type.titleMedium)
        }
        Item { width: 1; height: Spacing.xl }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.user
            color: Colors.surfaceOn
            font: Type.font(Type.titleMedium)
        }

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: root.shakeOffset
            width: 320
            height: 56
            radius: Shapes.full
            color: Colors.surfaceContainerHigh
            border.width: passwordInput.activeFocus ? 2 : 0
            border.color: root.error !== "" ? Colors.error : Colors.primary

            Icon {
                id: lockIcon
                anchors.left: parent.left
                anchors.leftMargin: Spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                name: root.busy ? "hourglass_top" : "lock"
                color: Colors.surfaceVariantOn
            }
            TextInput {
                id: passwordInput
                objectName: "lockPassword"
                anchors.left: lockIcon.right
                anchors.leftMargin: Spacing.md
                anchors.right: parent.right
                anchors.rightMargin: Spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                readOnly: root.busy
                echoMode: TextInput.Password
                passwordCharacter: "•"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                color: Colors.surfaceOn
                selectionColor: Colors.primary
                selectedTextColor: Colors.primaryOn
                font: Type.font(Type.bodyLarge)
                Keys.onReturnPressed: root.submit()
                Keys.onEnterPressed: root.submit()
                Keys.onEscapePressed: text = ""
                onTextChanged: if (text !== "" && root.error !== "") root.edited()
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: passwordInput.text === ""
                    text: root.busy ? "Checking…" : "Password"
                    color: Colors.surfaceVariantOn
                    font: passwordInput.font
                }
            }
        }

        Text {
            objectName: "lockError"
            anchors.horizontalCenter: parent.horizontalCenter
            height: Type.bodyMedium.lineHeight
            text: root.error !== "" ? root.error : root.message
            color: root.error !== "" ? Colors.error : Colors.surfaceVariantOn
            font: Type.font(Type.bodyMedium)
        }
    }
}
