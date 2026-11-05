// The Network page's backend (NetworkPage.qml has the interface): Wi-Fi and wired devices through Quickshell's
// Networking (NetworkManager). The window loads it only while the page is open (D31); while loaded and `scan` is
// on, the Wi-Fi device scans, so the list is fresh. A secured network that is not saved asks for its password
// first; one whose saved password is refused (NoSecrets) asks again. An Ethernet port switches off with
// NetworkManager's disconnect, which keeps it down until asked again, and on with its saved connection (D111).
import QtQuick
import QtQml
import Quickshell.Io
import Quickshell.Networking

Item {
    id: root

    property bool scan: true

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property bool available: Networking.devices.values.length > 0
    readonly property bool wifiAvailable: wifiDevice !== null && Networking.wifiHardwareEnabled
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var wifiNetworks: wifiDevice?.networks.values ?? []
    // one entry per name (the strongest), the connected one first, then by signal
    readonly property var networks: {
        const best = {};
        for (const n of wifiNetworks) {
            if (!n.name) continue;
            const b = best[n.name];
            if (!b || n.connected || (!b.connected && n.signalStrength > b.signalStrength)) best[n.name] = n;
        }
        return Object.values(best).map(n => ({
            id: n.name, name: n.name, signal: n.signalStrength, secure: n.security !== WifiSecurityType.Open,
            known: n.known, connected: n.connected, busy: n.stateChanging, error: failed[n.name] ?? ""
        })).sort((a, b) => (b.connected - a.connected) || (b.signal - a.signal));
    }
    readonly property var wiredDevices: Networking.devices.values.filter(d => d.type === DeviceType.Wired)
    readonly property var wired: wiredDevices.map(d => ({
        id: d.name, name: d.name, connected: d.connected, cable: d.hasLink,
        connecting: d.state === ConnectionState.Connecting, disconnecting: d.state === ConnectionState.Disconnecting,
        on: (d.connected || d.state === ConnectionState.Connecting) && d.state !== ConnectionState.Disconnecting
    }))
    property string asking: ""                  // the network whose password is asked for
    property var failed: ({})                   // name: why it did not connect

    function network(id) {
        return wifiNetworks.filter(n => n.name === id).sort((a, b) => b.signalStrength - a.signalStrength)[0] ?? null;
    }
    function fail(id, text) {
        const f = Object.assign({}, failed);
        if (text) f[id] = text;
        else delete f[id];
        failed = f;
    }
    function setWifiEnabled(on) {
        Networking.wifiEnabled = on;
    }
    function connect(id) {
        const n = networks.find(x => x.id === id);
        if (!n) return;
        fail(id, "");
        if (n.secure && !n.known) {
            asking = id;
            return;
        }
        asking = "";
        network(id)?.connect();
    }
    function connectWithPassword(id, password) {
        const n = network(id);
        asking = "";
        fail(id, "");
        if (n) n.connectWithPsk(password);
    }
    function cancelPassword() {
        asking = "";
    }
    function disconnect(id) {
        wifiNetworks.find(n => n.name === id && n.connected)?.disconnect();
    }
    function setWiredEnabled(id, on) {
        const d = wiredDevices.find(x => x.name === id);
        if (!d) return;
        if (!on) d.disconnect();
        else if (d.network) d.network.connect();
        else {
            // no saved connection Quickshell knows of: NetworkManager makes or picks one
            wiredUp.command = ["nmcli", "device", "connect", id];
            wiredUp.running = true;
        }
    }
    Process { id: wiredUp }
    function forget(id) {
        for (const n of wifiNetworks.filter(n => n.name === id && n.known)) n.forget();
        fail(id, "");
    }

    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: true
        when: root.scan && root.wifiDevice !== null && root.wifiEnabled
        restoreMode: Binding.RestoreValue
    }
    Instantiator {
        model: root.wifiDevice?.networks ?? null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectionFailed(reason) {
                if (reason === ConnectionFailReason.NoSecrets) {
                    root.fail(modelData.name, "Wrong password");
                    root.asking = modelData.name;
                } else {
                    root.fail(modelData.name, "Could not connect");
                }
            }
        }
    }
}
