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

    // Quick Settings' Wi-Fi page (plan 2.6): every access point the device sees, as plain data (Details.js), and
    // what it can do with one. A password goes to NetworkManager, which keeps it with the new connection.
    readonly property var wifiNetworks: (wifiDevice?.networks.values ?? []).map(n => ({
        name: n.name ?? "", signal: n.signalStrength ?? 0, connected: n.connected, known: n.known, busy: n.stateChanging,
        secure: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe,
        psk: n.security === WifiSecurityType.WpaPsk || n.security === WifiSecurityType.Wpa2Psk
             || n.security === WifiSecurityType.Sae
    }))
    readonly property bool wifiScanning: wifiDevice?.scannerEnabled ?? false

    function setWifiEnabled(on) {
        Networking.wifiEnabled = on;
    }
    function network(name) {
        return wifiDevice?.networks.values.find(n => n.name === name && n.connected)
            ?? wifiDevice?.networks.values.find(n => n.name === name) ?? null;
    }
    function connectWifi(name, psk) {
        const n = network(name);
        if (!n) return;
        if (psk) n.connectWithPsk(psk);
        else n.connect();
    }
    function disconnectWifi(name) {
        network(name)?.disconnect();
    }
    // Scanning while the page is open: NetworkManager looks for networks more often then
    function setWifiScanning(on) {
        if (wifiDevice) wifiDevice.scannerEnabled = on;
    }
}
