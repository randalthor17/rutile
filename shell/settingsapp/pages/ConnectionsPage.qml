// Connections (D110): Airplane mode, then the Network page (Wi-Fi and Ethernet) and the Bluetooth page, which were
// pages of their own. A page view: the app sets `app`, `store` and `backend` (ConnectionsBackend.qml, or the tests'
// fake), which has radios, airplane, setAirplane(b), and `network` and `bluetooth`, the two pages' backends (their
// views list what those have). The group here is `setting_connections.airplane`; the others are the two pages'.
// The two views are loaded by their files: Quickshell knows a folder's types only where the root imports it.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    spacing: Spacing.xl

    ListItem {
        objectName: "setting_connections.airplane"
        width: page.width
        tone: Colors.surfaceContainer
        iconName: "flight"
        text: "Airplane mode"
        supportingText: !(page.backend?.radios ?? false) ? "No Wi-Fi or Bluetooth" : "Wi-Fi and Bluetooth off"
        enabled: page.backend?.radios ?? false
        onClicked: page.backend.setAirplane(!page.backend.airplane)
        Switch {
            objectName: "airplaneSwitch"
            controlled: true
            checked: page.backend?.airplane ?? false
            enabled: page.backend?.radios ?? false
            onToggled: want => page.backend.setAirplane(want)
        }
    }
    Text {
        text: "Network"
        color: Colors.primary
        font: Type.font(Type.titleSmall)
    }
    Loader {
        id: network
        width: page.width
        source: Qt.resolvedUrl("NetworkPage.qml")
        Binding { target: network.item; property: "app"; value: page.app; when: network.status === Loader.Ready }
        Binding { target: network.item; property: "store"; value: page.store; when: network.status === Loader.Ready }
        Binding { target: network.item; property: "backend"; value: page.backend?.network ?? null; when: network.status === Loader.Ready }
    }
    Text {
        text: "Bluetooth"
        color: Colors.primary
        font: Type.font(Type.titleSmall)
    }
    Loader {
        id: bluetooth
        width: page.width
        source: Qt.resolvedUrl("BluetoothPage.qml")
        Binding { target: bluetooth.item; property: "app"; value: page.app; when: bluetooth.status === Loader.Ready }
        Binding { target: bluetooth.item; property: "store"; value: page.store; when: bluetooth.status === Loader.Ready }
        Binding { target: bluetooth.item; property: "backend"; value: page.backend?.bluetooth ?? null; when: bluetooth.status === Loader.Ready }
    }
}
