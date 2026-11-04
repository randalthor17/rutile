pragma ComponentBehavior: Bound
// A Quick Settings tile's detail page (plan 2.6), as Googlebook opens one in place of the tiles: back, the name and
// its switch, then the list. "wifi" lists the networks (Details.js orders them): a click connects, disconnects, or
// first asks for the password, typed in a field under that network (Enter connects, Escape cancels).
// A saved network has a button to forget it. Under the list, "Hidden network" asks for a network's name and its
// password (none for an open one) and joins it (D100). "bluetooth" lists the adapter's devices: a click connects (pairing first) or disconnects. The page asks the
// backend to scan or discover while it is shown. Plain QtQuick, through the panel's backend.
import QtQuick
import qs.common
import qs.components
import "Controls.js" as Controls
import "Details.js" as Details

Column {
    id: root

    required property var backend
    property string page: ""                // "wifi" | "bluetooth"
    property string askingFor: ""           // the network whose password is being typed
    property bool askingHidden: false       // a hidden network's name and password are being typed
    readonly property var live: Controls.state(page, backend)
    readonly property bool isWifi: page === "wifi"
    readonly property var rows: isWifi ? Details.networks(backend?.wifiNetworks)
                                       : Details.devices(backend?.bluetoothDevices)
    readonly property int maxRows: 6

    signal back()

    function activate(row) {
        if (isWifi) {
            const action = Details.networkAction(row);
            if (action === "disconnect") backend.disconnectWifi(row.name);
            else if (action === "connect") backend.connectWifi(row.name, "");
            else if (action === "password") {
                askingHidden = false;
                askingFor = askingFor === row.name ? "" : row.name;
                return;
            }
            askingFor = "";
        } else {
            const action = Details.deviceAction(row);
            if (action === "disconnect") backend.disconnectBluetooth(row.address);
            else if (action === "connect") backend.connectBluetooth(row.address);
        }
    }
    function sendPassword(text) {
        if (text === "") return;
        backend.connectWifi(askingFor, text);
        askingFor = "";
    }
    function joinHidden() {
        const name = hiddenName.text.trim();
        if (name === "") {
            hiddenName.input.forceActiveFocus();
            return;
        }
        backend.joinHiddenWifi(name, hiddenPassword.text);
        askingHidden = false;
    }
    function scan(on) {
        if (!backend) return;
        if (page === "wifi") backend.setWifiScanning(on);
        else if (page === "bluetooth") backend.setBluetoothDiscovering(on);
    }

    spacing: Spacing.md
    Component.onCompleted: scan(true)
    Component.onDestruction: scan(false)

    // ---- back, name, switch ----
    Item {
        width: parent.width
        height: ControlSpec.iconButtonSizes.s.height
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Spacing.sm
            IconButton {
                objectName: "qsDetailsBack"
                anchors.verticalCenter: parent.verticalCenter
                iconName: "arrow_back"
                onClicked: root.back()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Controls.catalog[root.page]?.text ?? ""
                color: Colors.surfaceOn
                font: Type.font(Type.titleMedium)
            }
        }
        Switch {
            objectName: "qsDetailsSwitch"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            controlled: true
            enabled: root.live.available
            checked: root.live.active
            onToggled: wanted => Controls.toggle(root.page, wanted, root.backend)
        }
    }

    // ---- the list ----
    Text {
        objectName: "qsDetailsEmpty"
        visible: root.rows.length === 0
        width: parent.width
        wrapMode: Text.Wrap
        text: !root.live.available ? "Unavailable"
            : !root.live.active ? (root.isWifi ? "Turn on Wi-Fi to see networks" : "Turn on Bluetooth to see devices")
            : (root.isWifi ? "Looking for networks…" : "Looking for devices…")
        color: Colors.surfaceVariantOn
        font: Type.font(Type.bodyMedium)
    }
    Flickable {
        id: flick
        visible: root.rows.length > 0
        width: parent.width
        height: Math.min(list.implicitHeight, root.maxRows * ControlSpec.listSpec.itemTwoLineContainerHeight)
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: list
            width: flick.width
            spacing: ControlSpec.listSpec.segmentedGap
            Repeater {
                model: root.rows
                delegate: Column {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string key: root.isWifi ? modelData.name : modelData.address
                    width: list.width
                    spacing: ControlSpec.listSpec.segmentedGap
                    ListItem {
                        objectName: "qsDetailsRow_" + row.key
                        width: parent.width
                        position: root.rows.length === 1 ? "single" : row.index === 0 ? "first"
                                : row.index === root.rows.length - 1 ? "last" : "middle"
                        tone: Colors.surfaceContainerHigh
                        selected: row.modelData.connected
                        iconName: root.isWifi ? Details.signalIcon(row.modelData.signal) : Details.deviceIcon(row.modelData.icon)
                        text: row.modelData.name
                        supportingText: root.isWifi ? Details.networkStatus(row.modelData) : Details.deviceStatus(row.modelData)
                        onClicked: root.activate(row.modelData)
                        // a saved network can be forgotten: NetworkManager drops its connection and password
                        IconButton {
                            objectName: "qsForget_" + row.key
                            visible: root.isWifi && row.modelData.known && !row.modelData.busy
                            size: "xs"
                            iconName: "delete"
                            Accessible.name: "Forget " + row.modelData.name
                            onClicked: root.backend.forgetWifi(row.modelData.name)
                        }
                    }
                    // the password, under its network
                    TextField {
                        property bool shown: false
                        objectName: "qsPassword_" + row.key
                        visible: root.isWifi && root.askingFor === row.key
                        width: parent.width
                        label: "Password"
                        password: !shown
                        trailingIconName: shown ? "visibility_off" : "visibility"
                        backgroundColor: Colors.surfaceContainer
                        onTrailingClicked: shown = !shown
                        onVisibleChanged: if (visible) { text = ""; shown = false; input.forceActiveFocus(); }
                        onAccepted: text => root.sendPassword(text)
                        Keys.onEscapePressed: event => {
                            root.askingFor = "";
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }

    // ---- a hidden network (D100) ----
    ListItem {
        objectName: "qsHiddenNetwork"
        visible: root.isWifi && root.live.active
        width: parent.width
        tone: Colors.surfaceContainerHigh
        iconName: "add"
        text: "Hidden network"
        supportingText: root.backend?.hiddenJoining ? "Joining " + root.backend.hiddenName + "…" : "Join a network by its name"
        onClicked: {
            root.askingFor = "";
            root.askingHidden = !root.askingHidden;
        }
    }
    TextField {
        id: hiddenName
        objectName: "qsHiddenName"
        visible: root.isWifi && root.askingHidden
        width: parent.width
        label: "Network name"
        backgroundColor: Colors.surfaceContainer
        onVisibleChanged: if (visible) { text = ""; input.forceActiveFocus(); }
        onAccepted: text => { if (text.trim() !== "") hiddenPassword.input.forceActiveFocus(); }
        Keys.onEscapePressed: event => {
            root.askingHidden = false;
            event.accepted = true;
        }
    }
    TextField {
        id: hiddenPassword
        property bool shown: false
        objectName: "qsHiddenPassword"
        visible: hiddenName.visible
        width: parent.width
        label: "Password"
        supportingText: "Leave empty for an open network"
        password: !shown
        trailingIconName: shown ? "visibility_off" : "visibility"
        backgroundColor: Colors.surfaceContainer
        onTrailingClicked: shown = !shown
        onVisibleChanged: if (visible) { text = ""; shown = false; }
        onAccepted: root.joinHidden()
        Keys.onEscapePressed: event => {
            root.askingHidden = false;
            event.accepted = true;
        }
    }
}
