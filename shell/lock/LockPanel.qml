// What the lock screen shows on each screen (plan 2.8): the time and date large in the middle, the user's name and a
// password field under them, over the wallpaper blurred and veiled in the surface color (or the plain surface when
// there is no wallpaper). Enter sends the password (`submitted`); while `busy` the field takes no typing; `error`
// shows under the field and the field shakes. `progress` (0 to 1, from LockScreen's spring) is the lock's motion:
// at 0 the wallpaper is sharp and nothing is on it, at 1 it is blurred and the clock and field have risen into
// place; unlocking runs it back to 0. Plain QtQuick, so it tests offscreen: LockScreen gives it the time, the user,
// the wallpaper and the state.
import QtQuick
import QtQuick.Effects
import qs.common
import qs.components
import "../bar/ClockText.js" as ClockText
import "LockWallpaper.js" as LockWallpaper

Rectangle {
    id: root

    required property date now
    property string user: ""
    property bool busy: false
    property string error: ""
    property string message: ""          // what PAM asks or tells, when it is not just the password
    property bool use24h: ClockText.uses24h(Qt.locale().timeFormat(Locale.ShortFormat))
    property string wallpaper: ""        // an image file's path; "" for none
    property real progress: 1            // the lock's motion, see above; may overshoot 1 a little (a spring)

    readonly property real shown: Math.max(0, Math.min(1, progress))
    readonly property bool hasWallpaper: wallpaperImage.status === Image.Ready
    // Ready to move: the wallpaper has loaded, failed, or there is none (the motion waits for it, so the wallpaper
    // blurs in with it instead of popping in after).
    readonly property bool backgroundReady: wallpaper === "" || wallpaperImage.status === Image.Ready
                                            || wallpaperImage.status === Image.Error

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

    // The wallpaper, small (it is only ever seen blurred), blurred as the lock comes in. LockWallpaper keeps the
    // same image at the same size loaded while unlocked, so this comes from Qt's image cache at once instead of
    // decoding a large file (a 4K PNG took 0.4 s) while the screen waits.
    Image {
        id: wallpaperImage
        anchors.fill: parent
        visible: false                   // drawn through the blur below
        source: LockWallpaper.url(root.wallpaper)
        sourceSize: LockWallpaper.size
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    MultiEffect {
        objectName: "lockBlur"
        anchors.fill: parent
        visible: root.hasWallpaper
        source: wallpaperImage
        blurEnabled: true
        blurMax: 64
        // never quite sharp: the small copy shows its pixels without some blur
        blur: root.minBlur + (1 - root.minBlur) * root.shown
        autoPaddingEnabled: false
    }
    readonly property real minBlur: 0.15
    // The wallpaper at the screen's size, loaded in the background once locked (only while locked, D31): it takes
    // over as the blur goes, so the end of unlocking is sharp, as the desktop it gives way to.
    Image {
        id: sharpImage
        objectName: "lockSharp"
        anchors.fill: parent
        source: root.hasWallpaper ? LockWallpaper.url(root.wallpaper) : ""
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: Math.max(0, 1 - 4 * root.shown)
        visible: status === Image.Ready && opacity > 0
    }
    // A veil in the surface color, so the text reads on any wallpaper in both modes.
    Rectangle {
        anchors.fill: parent
        visible: root.hasWallpaper
        color: Colors.surface
        opacity: 0.45 * root.shown
    }

    Column {
        id: content
        objectName: "lockContent"
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (1 - root.progress) * Spacing.xxxl
        opacity: root.shown
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
