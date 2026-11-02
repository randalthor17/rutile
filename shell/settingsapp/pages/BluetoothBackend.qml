// The Bluetooth page's backend (BluetoothPage.qml has the interface): the default adapter's devices through
// Quickshell's Bluetooth (BlueZ). The window loads it only while the page is open (D31); while loaded, `scan` on
// and the adapter on, it discovers devices, as Googlebook's page does. Pairing uses BlueZ's default agent: devices
// that ask to confirm a code need an agent of their own (not here yet).
import QtQuick
import QtQml
import Quickshell.Bluetooth

Item {
    id: root

    property bool scan: true

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: !!adapter
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false
    readonly property var all: adapter?.devices.values ?? []
    // paired first, then by name; devices that never said their name are left out
    readonly property var devices: all.filter(d => d.paired || d.name !== "" && d.name !== d.address.replace(/:/g, "-"))
        .map(d => ({
            id: d.address, name: d.name || d.address, icon: d.icon, paired: d.paired, connected: d.connected,
            busy: d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting,
            battery: d.batteryAvailable ? d.battery : -1
        }))
        .sort((a, b) => (b.paired - a.paired) || (b.connected - a.connected) || a.name.localeCompare(b.name))

    property var pairingHere: ({})            // devices paired from this page: they connect once paired

    function device(id) {
        return all.find(d => d.address === id) ?? null;
    }
    function setEnabled(on) {
        if (adapter) adapter.enabled = on;
    }
    // a paired device connects or disconnects; another pairs, is trusted (so it reconnects) and connects
    function toggle(id) {
        const d = device(id);
        if (!d) return;
        if (d.connected) d.disconnect();
        else if (d.paired) d.connect();
        else {
            const p = Object.assign({}, pairingHere);
            p[id] = true;
            pairingHere = p;
            d.trusted = true;
            d.pair();
        }
    }
    function forget(id) {
        device(id)?.forget();
    }

    Binding {
        target: root.adapter
        property: "discovering"
        value: true
        when: root.scan && root.enabled
        restoreMode: Binding.RestoreValue
    }
    // a device just paired here connects (pair() alone leaves it disconnected)
    Instantiator {
        model: root.adapter?.devices ?? null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPairedChanged() {
                if (modelData.paired && !modelData.connected && root.pairingHere[modelData.address]) modelData.connect();
            }
        }
    }
}
