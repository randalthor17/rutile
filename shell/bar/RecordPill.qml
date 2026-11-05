// While the screen is being recorded (D120), left of the input method: a red dot and how long it has run; a click
// stops it. Plain QtQuick, so it tests offscreen: `since` is when it started (ms), `now` advances each second
// while it shows.
import QtQuick
import qs.common
import qs.components
import "../capture/Capture.js" as Capture

Rectangle {
    id: root

    property bool recording: false
    property real since: 0
    property real now: Date.now()

    signal clicked()

    visible: recording
    implicitWidth: visible ? row.width + 2 * Spacing.sm : 0
    implicitHeight: Spacing.xl
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: Panels.tint(Colors.errorContainer)

    Accessible.role: Accessible.Button
    Accessible.name: "Stop recording"

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.visible
        onTriggered: root.now = Date.now()
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Spacing.xs
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Spacing.sm
            height: width
            radius: width / 2
            color: Colors.error
        }
        Text {
            objectName: "recordTime"
            anchors.verticalCenter: parent.verticalCenter
            text: Capture.elapsed((root.now - root.since) / 1000)
            color: Colors.errorContainerOn
            font: Type.font(Type.labelLarge)
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "stop"
            size: Spacing.lg
            fill: 1
            color: Colors.errorContainerOn
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        stateColor: Colors.errorContainerOn
        onClicked: root.clicked()
    }
}
