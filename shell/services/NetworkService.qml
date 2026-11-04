// Wi-Fi through Quickshell's Networking service (NetworkManager). `wifiEnabled` is the rfkill software
// switch for every wireless device; `wifiAvailable` is false with no Wi-Fi device or a hardware block.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
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
    function forgetWifi(name) {
        network(name)?.forget();
    }
    // A hidden network (D100), which no scan lists: hidden-wifi.sh asks NetworkManager (nmcli) to join it by name.
    // The password goes to the script on stdin, never in its arguments, and is dropped once written. A failure
    // shows as a toast; a success shows as the network connected in the list.
    readonly property bool hiddenJoining: hiddenJoin.joining
    readonly property string hiddenName: hiddenJoin.name
    function joinHiddenWifi(name, password) {
        if (hiddenJoin.joining || name === "") return false;
        hiddenJoin.joining = true;              // at once: `running` turns true only once it has started
        hiddenJoin.name = name;
        hiddenJoin.password = password;
        hiddenJoin.command = ["sh", root.hiddenScript, name, password ? "psk" : "open"];
        hiddenJoin.running = true;
        return true;
    }
    readonly property string hiddenScript: Qt.resolvedUrl("hidden-wifi.sh").toString().replace("file://", "")
    Process {
        id: hiddenJoin
        property string name: ""
        property string password: ""
        property bool joining: false
        stdinEnabled: true
        onStarted: {
            if (password !== "") write(password + "\n");
            password = "";
            stdinEnabled = false;                // closes it: the script reads to its end
        }
        stderr: StdioCollector { id: hiddenErrors }
        onExited: code => {
            password = "";
            stdinEnabled = true;
            joining = false;
            if (code !== 0) {
                console.warn("network: joining hidden", name, "failed:", hiddenErrors.text.trim());
                ToastService.show("Couldn't join " + name, { icon: "wifi_off" });
            }
        }
    }

    // Scanning while the page is open: NetworkManager looks for networks more often then
    function setWifiScanning(on) {
        if (wifiDevice) wifiDevice.scannerEnabled = on;
    }
}
