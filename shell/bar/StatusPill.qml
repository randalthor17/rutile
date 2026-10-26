// The status pill at the top right (Googlebook): network, volume and battery at a glance; a click opens Quick
// Settings. Plain QtQuick on the same backend as Quick Settings (QuickSettingsBackend.qml), so it tests
// offscreen with a fake. Extra backend members: wifiSignal, wiredConnected, batteryAvailable, battery, charging.
// `open` marks it while the panel it opens is showing.
import QtQuick
import qs.common
import qs.components
import "StatusIcons.js" as StatusIcons

Rectangle {
    id: root

    required property var backend
    property bool open: false

    signal clicked()

    readonly property string networkIcon: backend ? StatusIcons.network(backend) : ""
    readonly property string volumeIcon: backend ? StatusIcons.volume(backend) : ""
    readonly property string batteryIcon: backend ? StatusIcons.battery(backend) : ""
    readonly property string batteryText: batteryIcon !== "" ? Math.round(backend.battery * 100) + "%" : ""
    // With nothing to report (no network, audio or battery) the pill still needs something to click.
    readonly property bool empty: networkIcon === "" && volumeIcon === "" && batteryIcon === ""

    // Googlebook's status icons are small and close; a tonal container keeps them readable on any wallpaper.
    implicitWidth: row.implicitWidth + 2 * Spacing.sm
    implicitHeight: Spacing.xl
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: open ? Colors.secondaryContainer : Colors.surfaceContainer
    Behavior on color { EffectsColor {} }

    readonly property color contentColor: open ? Colors.secondaryContainerOn : Colors.surfaceOn

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Spacing.xs
        Icon {
            objectName: "statusIcons"
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth        // several ligatures in one Text: one Icon instead of three (D31)
            name: root.empty ? "tune" : [root.networkIcon, root.volumeIcon, root.batteryIcon].filter(n => n !== "").join(" ")
            size: Spacing.lg
            fill: root.empty ? 0 : 1
            color: root.contentColor
        }
        Text {
            objectName: "statusBatteryText"
            anchors.verticalCenter: parent.verticalCenter
            visible: root.batteryText !== ""
            text: root.batteryText
            color: root.contentColor
            font: Type.font(Type.labelMedium)
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        stateColor: root.contentColor
        onClicked: root.clicked()
    }
}
