// Network (plan 5.2): Wi-Fi (its switch, the networks around, a password when one is needed) and wired devices.
// A page view: the app sets `app`, `store` and `backend` (NetworkBackend.qml, or the tests' fake), which has
//   available, wifiAvailable, wifiEnabled; networks: [(id, name, signal 0-1, secure, known, connected, busy,
//   error)]; wired: [(id, name, connected, on (connected or connecting), connecting, disconnecting, cable)]; asking: the network whose
//   password is wanted ("" for none); setWifiEnabled(b), connect(id), connectWithPassword(id, password),
//   cancelPassword(), disconnect(id), forget(id), setWiredEnabled(id, b) (an Ethernet port's switch, D111).
// The groups are `setting_network.wifi` and `setting_network.ethernet` (Pages.js entries).
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
    readonly property bool wifiOn: (backend?.wifiAvailable ?? false) && (backend?.wifiEnabled ?? false)
    readonly property var networks: wifiOn ? backend.networks ?? [] : []
    readonly property var wired: backend?.wired ?? []

    function segment(i, n) {
        return app ? app.segment(i, n) : "single";
    }
    function signalIcon(s) {
        return s >= 0.75 ? "signal_wifi_4_bar" : s >= 0.5 ? "network_wifi_3_bar" : s >= 0.25 ? "network_wifi_2_bar"
                                                                                           : "network_wifi_1_bar";
    }

    spacing: Spacing.xl

    ListItem {
        objectName: "networkUnavailable"
        visible: !page.available
        width: page.width
        iconName: "wifi_off"
        text: "No network service"
        supportingText: "NetworkManager is not running"
    }

    Column {
        objectName: "setting_network.wifi"
        visible: page.available
        width: page.width
        spacing: ControlSpec.listSpec.segmentedGap
        readonly property int rows: 1 + (page.wifiOn ? Math.max(1, page.networks.length) : 0)

        Text {
            height: implicitHeight + Spacing.sm
            leftPadding: Spacing.lg
            text: "Wi-Fi"
            color: Colors.primary
            font: Type.font(Type.titleSmall)
        }
        ListItem {
            id: wifiRow
            objectName: "networkWifi"
            width: page.width
            position: page.segment(0, parent.rows)
            tone: Colors.surfaceContainer
            iconName: page.wifiOn ? "wifi" : "wifi_off"
            text: "Wi-Fi"
            supportingText: !(page.backend?.wifiAvailable ?? false) ? "No Wi-Fi device, or switched off by hardware"
                                                                    : page.wifiOn ? "On" : "Off"
            enabled: page.backend?.wifiAvailable ?? false
            onClicked: page.backend.setWifiEnabled(!page.backend.wifiEnabled)
            Switch {
                objectName: "networkWifiSwitch"
                controlled: true
                checked: page.wifiOn
                enabled: wifiRow.enabled
                onToggled: want => page.backend.setWifiEnabled(want)
            }
        }
        ListItem {
            objectName: "networkSearching"
            visible: page.wifiOn && page.networks.length === 0
            width: page.width
            position: "last"
            tone: Colors.surfaceContainer
            text: "Looking for networks…"
            enabled: false
        }
        Repeater {
            model: page.networks
            delegate: Column {
                id: net
                required property var modelData
                required property int index
                readonly property bool asked: page.backend.asking === modelData.id
                width: page.width
                spacing: ControlSpec.listSpec.segmentedGap

                ListItem {
                    objectName: "network_" + net.index
                    width: page.width
                    position: page.segment(net.index + 1, 1 + page.networks.length)
                    tone: Colors.surfaceContainer
                    iconName: page.signalIcon(net.modelData.signal)
                    text: net.modelData.name
                    supportingText: net.modelData.connected ? "Connected"
                                  : net.modelData.busy ? "Connecting…"
                                  : net.modelData.error !== "" ? net.modelData.error
                                  : net.modelData.known ? "Saved" : ""
                    selected: net.modelData.connected
                    onClicked: {
                        if (net.modelData.connected) page.backend.disconnect(net.modelData.id);
                        else page.backend.connect(net.modelData.id);
                    }
                    Row {
                        spacing: Spacing.xs
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: net.modelData.secure
                            name: "lock"
                            color: Colors.surfaceVariantOn
                        }
                        IconButton {
                            objectName: "networkForget_" + net.index
                            anchors.verticalCenter: parent.verticalCenter
                            visible: net.modelData.known
                            iconName: "delete"
                            Accessible.name: "Forget " + net.modelData.name
                            onClicked: page.backend.forget(net.modelData.id)
                        }
                    }
                }
                // the password, under its network
                Rectangle {
                    objectName: "networkPasswordBox"
                    visible: net.asked
                    width: page.width
                    height: visible ? 72 : 0
                    radius: Shapes.medium
                    color: Colors.surfaceContainer
                    onVisibleChanged: if (visible) password.forceActiveFocus()

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: buttons.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Spacing.lg
                        height: 48
                        radius: Shapes.full
                        color: Colors.surfaceContainerLowest
                        border.width: password.activeFocus ? 2 : 1
                        border.color: password.activeFocus ? Colors.primary : Colors.outlineVariant
                        TextInput {
                            id: password
                            objectName: "networkPassword"
                            anchors.fill: parent
                            anchors.leftMargin: Spacing.lg
                            anchors.rightMargin: Spacing.lg
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            echoMode: TextInput.Password
                            color: Colors.surfaceOn
                            selectionColor: Colors.primary
                            selectedTextColor: Colors.primaryOn
                            font: Type.font(Type.bodyLarge)
                            function submit() {
                                if (text === "") return;
                                page.backend.connectWithPassword(net.modelData.id, text);
                                text = "";
                            }
                            Keys.onReturnPressed: submit()
                            Keys.onEnterPressed: submit()
                            Keys.onEscapePressed: {
                                text = "";
                                page.backend.cancelPassword();
                            }
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: password.text === ""
                                text: "Password for " + net.modelData.name
                                color: Colors.surfaceVariantOn
                                font: Type.font(Type.bodyLarge)
                            }
                        }
                    }
                    Row {
                        id: buttons
                        anchors.right: parent.right
                        anchors.rightMargin: Spacing.lg
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Spacing.sm
                        Button {
                            objectName: "networkPasswordCancel"
                            type: "text"
                            size: "s"
                            text: "Cancel"
                            onClicked: {
                                password.text = "";
                                page.backend.cancelPassword();
                            }
                        }
                        Button {
                            objectName: "networkPasswordConnect"
                            type: "filled"
                            size: "s"
                            text: "Connect"
                            enabled: password.text !== ""
                            onClicked: password.submit()
                        }
                    }
                }
            }
        }
    }

    Column {
        objectName: "setting_network.ethernet"
        visible: page.available && page.wired.length > 0
        width: page.width
        spacing: ControlSpec.listSpec.segmentedGap

        Text {
            height: implicitHeight + Spacing.sm
            leftPadding: Spacing.lg
            text: "Ethernet"
            color: Colors.primary
            font: Type.font(Type.titleSmall)
        }
        Repeater {
            model: page.wired
            delegate: ListItem {
                id: port
                required property var modelData
                required property int index
                // off with no cable there is nothing to turn on
                readonly property bool busy: !!modelData.connecting || !!modelData.disconnecting
                readonly property bool switchable: !busy && (modelData.on || modelData.cable !== false)
                objectName: "networkWired_" + index
                width: page.width
                position: page.segment(index, page.wired.length)
                tone: Colors.surfaceContainer
                iconName: "lan"
                text: modelData.connecting ? "Connecting…" : modelData.disconnecting ? "Disconnecting…"
                    : modelData.connected ? "Connected" : modelData.cable === false ? "No cable" : "Off"
                supportingText: modelData.name
                selected: modelData.connected
                enabled: port.switchable
                onClicked: page.backend.setWiredEnabled(modelData.id, !modelData.on)
                Switch {
                    objectName: "networkWiredSwitch_" + port.index
                    controlled: true
                    checked: port.modelData.on
                    enabled: port.switchable
                    onToggled: want => page.backend.setWiredEnabled(port.modelData.id, want)
                }
            }
        }
    }
}
