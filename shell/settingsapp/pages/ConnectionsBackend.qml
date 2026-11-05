// The Connections page's backend (ConnectionsPage.qml has the interface, D110): the Network and Bluetooth pages'
// backends, loaded together while the page is open (D31), and Airplane mode over both. Airplane mode is on while
// every radio there is is off, as Quick Settings' tile shows it; turning it on turns them off, and off turns them on.
// The two are loaded by their files: Quickshell knows a folder's types only where the root imports that folder.
import QtQuick

Item {
    id: root

    readonly property var network: networkLoader.item
    readonly property var bluetooth: bluetoothLoader.item
    readonly property bool radios: (network?.wifiAvailable ?? false) || (bluetooth?.available ?? false)
    readonly property bool airplane: radios && !(network.wifiAvailable && network.wifiEnabled)
                                     && !(bluetooth.available && bluetooth.enabled)

    function setAirplane(on) {
        if (network?.wifiAvailable) network.setWifiEnabled(!on);
        if (bluetooth?.available) bluetooth.setEnabled(!on);
    }

    Loader { id: networkLoader; source: Qt.resolvedUrl("NetworkBackend.qml") }
    Loader { id: bluetoothLoader; source: Qt.resolvedUrl("BluetoothBackend.qml") }
}
