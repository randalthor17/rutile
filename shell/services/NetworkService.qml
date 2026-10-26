// Wi-Fi through Quickshell's Networking service (NetworkManager). `wifiEnabled` is the rfkill software
// switch for every wireless device; `wifiAvailable` is false with no Wi-Fi device or a hardware block.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    id: root

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property bool wifiAvailable: wifiDevice !== null && Networking.wifiHardwareEnabled
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var wifiNetwork: wifiDevice?.networks.values.find(n => n.connected) ?? null
    readonly property string wifiName: wifiNetwork?.name ?? ""
    readonly property real wifiSignal: wifiNetwork?.signalStrength ?? 0     // 0..1
    readonly property bool wiredConnected: Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected)

    function setWifiEnabled(on) {
        Networking.wifiEnabled = on;
    }
}
