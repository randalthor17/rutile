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

    function setEnabled(on) {
        if (adapter) adapter.enabled = on;
    }
}
