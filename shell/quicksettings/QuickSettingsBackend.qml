// The shell's backend for Quick Settings and the status pill: the interface QuickSettingsPanel.qml and
// StatusPill.qml list, on top of the Quickshell services in shell/services. The shell makes one; tests and the
// gallery use fakes with the same names.
import QtQuick
import qs.common
import qs.services

QtObject {
    readonly property bool brightnessAvailable: BrightnessService.available
    readonly property real brightness: BrightnessService.value
    readonly property bool volumeAvailable: AudioService.available
    readonly property real volume: AudioService.volume
    readonly property bool muted: AudioService.muted
    readonly property bool micAvailable: AudioService.micAvailable
    readonly property bool micMuted: AudioService.micMuted
    readonly property bool wifiAvailable: NetworkService.wifiAvailable
    readonly property bool wifiEnabled: NetworkService.wifiEnabled
    readonly property string wifiName: NetworkService.wifiName
    readonly property real wifiSignal: NetworkService.wifiSignal
    readonly property bool wiredConnected: NetworkService.wiredConnected
    readonly property bool batteryAvailable: PowerService.batteryAvailable
    readonly property real battery: PowerService.battery
    readonly property bool charging: PowerService.charging
    readonly property bool bluetoothAvailable: BluetoothService.available
    readonly property bool bluetoothEnabled: BluetoothService.enabled
    readonly property string bluetoothDevice: BluetoothService.connectedName
    // In-session only until settings persistence (plan 2.5); palette.json carries both modes.
    readonly property bool darkTheme: Colors.mode === "dark"

    function setBrightness(v) { BrightnessService.set(v); }
    function setVolume(v) { AudioService.setVolume(v); }
    function setMicMuted(m) { AudioService.setMicMuted(m); }
    function setWifiEnabled(on) { NetworkService.setWifiEnabled(on); }
    function setBluetoothEnabled(on) { BluetoothService.setEnabled(on); }
    function setDarkTheme(on) { Colors.mode = on ? "dark" : "light"; }
    // Airplane mode turns every radio off; turning it off turns them back on.
    function setAirplaneMode(on) {
        NetworkService.setWifiEnabled(!on);
        BluetoothService.setEnabled(!on);
    }
    function refresh() { BrightnessService.refresh(); }
}
