// The capture bar (D120), as ChromeOS's screen capture: Screenshot or Record, then what to take: a region, a window
// (screenshots only, and only on niri) or the screen; the microphone for a recording; close. Choosing what to take
// asks for it (`captureRequested`) and the shell takes it once the bar is gone. Escape closes. Plain QtQuick, so it
// tests offscreen; it grows in and out with the shared popup motion (D43), then reports `hidden`.
import QtQuick
import qs.common
import qs.components

Rectangle {
    id: root

    property bool record: false
    property bool audio: false
    property bool windows: true             // a window can be taken (niri)
    property bool shown: true

    signal captureRequested(string mode, string target, bool audio)
    signal closeRequested()
    signal hidden()

    function take(target) {
        root.captureRequested(record ? "record" : "screenshot", target, record && audio);
    }

    implicitWidth: row.width + 2 * Spacing.sm
    implicitHeight: row.height + 2 * Spacing.sm
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: Panels.tint(Colors.surfaceContainer)

    focus: true
    Keys.onEscapePressed: root.closeRequested()

    PopupMotion {
        target: root
        shown: root.shown
        origin: Item.Bottom
        onHidden: root.hidden()
    }

    Row {
        id: row
        x: Spacing.sm
        y: Spacing.sm
        spacing: Spacing.xs

        IconButton {
            objectName: "captureModeScreenshot"
            size: "m"
            iconName: "photo_camera"
            toggle: true
            checked: !root.record
            onClicked: root.record = false
        }
        IconButton {
            objectName: "captureModeRecord"
            size: "m"
            iconName: "videocam"
            toggle: true
            checked: root.record
            onClicked: root.record = true
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Spacing.xl
            color: Colors.outlineVariant
        }
        IconButton {
            objectName: "captureRegion"
            size: "m"
            type: "tonal"
            iconName: "screenshot_region"
            onClicked: root.take("region")
        }
        IconButton {
            objectName: "captureWindow"
            size: "m"
            type: "tonal"
            iconName: "web_asset"
            visible: root.windows && !root.record
            onClicked: root.take("window")
        }
        IconButton {
            objectName: "captureScreen"
            size: "m"
            type: "tonal"
            iconName: "screenshot_monitor"
            onClicked: root.take("screen")
        }
        IconButton {
            objectName: "captureAudio"
            size: "m"
            visible: root.record
            iconName: root.audio ? "mic" : "mic_off"
            toggle: true
            checked: root.audio
            onClicked: root.audio = !root.audio
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Spacing.xl
            color: Colors.outlineVariant
        }
        IconButton {
            objectName: "captureClose"
            size: "m"
            iconName: "close"
            onClicked: root.closeRequested()
        }
    }
}
