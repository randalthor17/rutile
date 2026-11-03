// The default Bluetooth adapter through Quickshell's Bluetooth service (BlueZ).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: !!adapter
    readonly property bool enabled: adapter?.enabled ?? false
    // Bluetooth.devices holds the connected devices of every adapter.
    readonly property string connectedName: Bluetooth.devices.values.find(d => d.connected)?.name ?? ""

    // Quick Settings' Bluetooth page (plan 2.6): the default adapter's devices as plain data (Details.js); it
    // looks for new ones (discovering) while the page is open.
    readonly property var devices: (adapter?.devices.values ?? []).map(d => ({
        address: d.address, name: d.name || d.deviceName || d.address, named: !!(d.name || d.deviceName),
        icon: d.icon ?? "", connected: d.connected, paired: d.paired, battery: d.batteryAvailable ? d.battery : -1,
        busy: d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting
    }))
    readonly property bool discovering: adapter?.discovering ?? false

    function setEnabled(on) {
        if (adapter) adapter.enabled = on;
    }
    function device(address) {
        return adapter?.devices.values.find(d => d.address === address) ?? null;
    }
    // A device not paired yet is trusted and paired first; BlueZ connects it once paired (pairedChanged below)
    function connectDevice(address) {
        const d = device(address);
        if (!d) return;
        if (d.paired) {
            d.connect();
        } else {
            d.trusted = true;
            pending = address;
            d.pair();
        }
    }
    function disconnectDevice(address) {
        device(address)?.disconnect();
    }
    function setDiscovering(on) {
        if (adapter && adapter.enabled) adapter.discovering = on;
    }

    // the device being paired to connect, once it is
    property string pending: ""
    readonly property bool pendingPaired: pending !== "" && (device(pending)?.paired ?? false)
    onPendingPairedChanged: {
        if (!pendingPaired) return;
        const d = device(pending);
        pending = "";
        d?.connect();
    }
}
