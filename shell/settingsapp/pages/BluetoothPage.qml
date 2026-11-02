// Bluetooth (plan 5.2): the switch, paired devices (connect, disconnect, forget) and the devices around to pair.
// A page view: the app sets `app`, `store` and `backend` (BluetoothBackend.qml, or the tests' fake), which has
//   available, enabled, discovering; devices: [{id, name, icon (BlueZ's), paired, connected, busy, battery (0-1,
//   -1 unknown)}]; setEnabled(b), toggle(id) (connect, disconnect, or pair), forget(id).
// The groups are `setting_bluetooth.paired` and `setting_bluetooth.available` (Pages.js entries).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    readonly property bool available: backend?.available ?? false
    readonly property bool on: available && (backend?.enabled ?? false)
    readonly property var devices: on ? backend.devices ?? [] : []
    readonly property var paired: devices.filter(d => d.paired)
    readonly property var others: devices.filter(d => !d.paired)

    function segment(i, n) {
        return app ? app.segment(i, n) : "single";
    }
    // BlueZ's icon names (freedesktop's) as Material Symbols
    function symbol(icon) {
        const map = { "audio-headset": "headset_mic", "audio-headphones": "headphones", "audio-card": "speaker",
                      "input-mouse": "mouse", "input-keyboard": "keyboard", "input-gaming": "sports_esports",
                      "input-tablet": "stylus", "phone": "smartphone", "computer": "computer",
                      "video-display": "tv", "camera-photo": "photo_camera", "printer": "print" };
        return map[icon] ?? "bluetooth";
    }
    function status(d) {
        if (d.busy) return d.paired ? (d.connected ? "Disconnecting…" : "Connecting…") : "Pairing…";
        if (d.connected) return d.battery >= 0 ? "Connected, battery " + Math.round(d.battery * 100) + "%" : "Connected";
        return d.paired ? "Not connected" : "";
    }

    spacing: Spacing.xl

    ListItem {
        objectName: "bluetoothSwitchRow"
        width: page.width
        tone: Colors.surfaceContainer
        iconName: page.on ? "bluetooth" : "bluetooth_disabled"
        text: "Bluetooth"
        supportingText: !page.available ? "No Bluetooth adapter" : page.on ? "On" : "Off"
        enabled: page.available
        onClicked: page.backend.setEnabled(!page.on)
        Switch {
            objectName: "bluetoothSwitch"
            controlled: true
            checked: page.on
            enabled: page.available
            onToggled: want => page.backend.setEnabled(want)
        }
    }

    Repeater {
        model: page.on ? [{ key: "paired", title: "Paired devices" }, { key: "available", title: "Available devices" }] : []
        delegate: Column {
            id: group
            required property var modelData
            readonly property var list: modelData.key === "paired" ? page.paired : page.others
            objectName: "setting_bluetooth." + modelData.key
            width: page.width
            spacing: ControlSpec.listSpec.segmentedGap

            Text {
                height: implicitHeight + Spacing.sm
                leftPadding: Spacing.lg
                text: group.modelData.title
                color: Colors.primary
                font: Type.font(Type.titleSmall)
            }
            ListItem {
                objectName: "bluetoothEmpty_" + group.modelData.key
                visible: group.list.length === 0
                width: page.width
                tone: Colors.surfaceContainer
                text: group.modelData.key === "paired" ? "No paired devices"
                    : (page.backend?.discovering ?? false) ? "Looking for devices…" : "No devices found"
                enabled: false
            }
            Repeater {
                model: group.list
                delegate: ListItem {
                    id: dev
                    required property var modelData
                    required property int index
                    objectName: "bluetooth_" + group.modelData.key + "_" + index
                    width: page.width
                    position: page.segment(index, group.list.length)
                    tone: Colors.surfaceContainer
                    iconName: page.symbol(modelData.icon)
                    text: modelData.name
                    supportingText: page.status(modelData)
                    selected: modelData.connected
                    enabled: !modelData.busy
                    onClicked: page.backend.toggle(modelData.id)
                    IconButton {
                        objectName: "bluetoothForget_" + dev.index
                        visible: dev.modelData.paired
                        iconName: "delete"
                        Accessible.name: "Forget " + dev.modelData.name
                        onClicked: page.backend.forget(dev.modelData.id)
                    }
                }
            }
        }
    }
}
