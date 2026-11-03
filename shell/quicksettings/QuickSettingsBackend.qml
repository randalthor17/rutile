// The shell's backend for Quick Settings and the status pill: the interface QuickSettingsPanel.qml and
// StatusPill.qml list, on top of the Quickshell services in shell/services. The shell makes one; tests and the
// gallery use fakes with the same names.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
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
    // the style's mode (D65): the shell's palette and the apps that take its colors; saved
    readonly property bool darkTheme: Settings.value("style.mode") === "dark"
    readonly property bool dnd: NotificationService.dnd
    // Power saver needs power-profiles-daemon, which Quickshell cannot tell is there: `busctl` looks for it once,
    // when Quick Settings first opens (refresh), and PowerProfiles is not touched before it is found
    property bool powerSaverAvailable: false
    readonly property bool powerSaver: powerSaverAvailable && PowerProfiles.profile === PowerProfile.PowerSaver
    property Process profilesProbe: Process {
        command: ["busctl", "--system", "list", "--no-legend", "--no-pager"]
        stdout: StdioCollector {
            onStreamFinished: powerSaverAvailable = /^(net\.hadess|org\.freedesktop\.UPower)\.PowerProfiles\s/m.test(text)
        }
    }
    property bool probed: false

    function setBrightness(v) { BrightnessService.set(v); }
    function setVolume(v) { AudioService.setVolume(v); }
    function setMicMuted(m) { AudioService.setMicMuted(m); }
    function setWifiEnabled(on) { NetworkService.setWifiEnabled(on); }
    function setBluetoothEnabled(on) { BluetoothService.setEnabled(on); }
    function setDarkTheme(on) { Settings.set("style.mode", on ? "dark" : "light"); }
    // Airplane mode turns every radio off; turning it off turns them back on.
    function setAirplaneMode(on) {
        NetworkService.setWifiEnabled(!on);
        BluetoothService.setEnabled(!on);
    }
    // the detail pages (Details.js has the shapes)
    readonly property var wifiNetworks: NetworkService.wifiNetworks
    readonly property var bluetoothDevices: BluetoothService.devices
    function connectWifi(name, psk) { NetworkService.connectWifi(name, psk); }
    function disconnectWifi(name) { NetworkService.disconnectWifi(name); }
    function forgetWifi(name) { NetworkService.forgetWifi(name); }
    function setWifiScanning(on) { NetworkService.setWifiScanning(on); }
    function connectBluetooth(address) { BluetoothService.connectDevice(address); }
    function disconnectBluetooth(address) { BluetoothService.disconnectDevice(address); }
    function setBluetoothDiscovering(on) { BluetoothService.setDiscovering(on); }
    function setDnd(on) { NotificationService.setDnd(on); }
    function setPowerSaver(on) {
        if (powerSaverAvailable)
            PowerProfiles.profile = on ? PowerProfile.PowerSaver : PowerProfile.Balanced;
    }
    function refresh() {
        BrightnessService.refresh();
        if (!probed) {
            probed = true;
            profilesProbe.running = true;
        }
    }
}
