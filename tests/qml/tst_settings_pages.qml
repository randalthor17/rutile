// The settings app's pages of their own (plan 5.2, D67) beyond Sound: Network and Bluetooth, each with a fake
// backend that has the page's interface and records what it is asked.
import QtQuick
import QtTest
import qs.common
import qs.settingsapp
import "../qs/settingsapp/Model.js" as Model
import "../qs/settingsapp/Pages.js" as Pages
import "../qs/services/SettingsSchema.js" as Schema

TestCase {
    id: root
    name: "SettingsPages"
    width: 1100
    height: 900
    visible: true
    when: windowShown

    Component {
        id: storeComp
        QtObject {
            readonly property string configDir: "/home/u/.config/rutile"
            function value(key) { return undefined; }
            function isManaged(key) { return false; }
            function set(key, value) { return false; }
        }
    }
    Component { id: appComp; SettingsApp { anchors.fill: parent } }

    Component {
        id: networkComp
        QtObject {
            property bool available: true
            property bool wifiAvailable: true
            property bool wifiEnabled: true
            property var networks: [
                { id: "Home", name: "Home", signal: 0.9, secure: true, known: true, connected: true, busy: false, error: "" },
                { id: "Cafe", name: "Cafe", signal: 0.4, secure: false, known: false, connected: false, busy: false, error: "" },
                { id: "Office", name: "Office", signal: 0.6, secure: true, known: false, connected: false, busy: false, error: "" }
            ]
            property var wired: [{ id: "enp5s0", name: "enp5s0", connected: false }]
            property string asking: ""
            property var calls: []
            function call(c) { calls = calls.concat([c]); }
            function setWifiEnabled(on) { call("wifi:" + on); wifiEnabled = on; }
            // as the real one: a secured network not saved asks for its password first
            function connect(id) {
                call("connect:" + id);
                const n = networks.find(x => x.id === id);
                if (n.secure && !n.known) asking = id;
            }
            function connectWithPassword(id, pw) { call("password:" + id + ":" + pw); asking = ""; }
            function cancelPassword() { call("cancel"); asking = ""; }
            function disconnect(id) { call("disconnect:" + id); }
            function forget(id) { call("forget:" + id); }
        }
    }
    Component {
        id: bluetoothComp
        QtObject {
            property bool available: true
            property bool enabled: true
            property bool discovering: true
            property var devices: [
                { id: "AA", name: "Buds", icon: "audio-headphones", paired: true, connected: true, busy: false, battery: 0.8 },
                { id: "BB", name: "Mouse", icon: "input-mouse", paired: true, connected: false, busy: false, battery: -1 },
                { id: "CC", name: "Speaker", icon: "audio-card", paired: false, connected: false, busy: false, battery: -1 }
            ]
            property var calls: []
            function call(c) { calls = calls.concat([c]); }
            function setEnabled(on) { call("enabled:" + on); enabled = on; }
            function toggle(id) { call("toggle:" + id); }
            function forget(id) { call("forget:" + id); }
        }
    }

    function make(page, backendComp) {
        const s = createTemporaryObject(storeComp, root);
        const a = createTemporaryObject(appComp, root, { store: s });
        const b = createTemporaryObject(backendComp, root);
        a.backend = b;
        verify(a.openPage(page));
        waitForRendering(a);
        return { a: a, b: b };
    }

    function test_network() {
        const t = make("network", networkComp);
        const a = t.a, b = t.b;
        verify(!findChild(a, "networkUnavailable").visible);
        verify(findChild(a, "networkWifiSwitch").checked);
        compare(findChild(a, "network_0").text, "Home");
        compare(findChild(a, "network_0").supportingText, "Connected");
        verify(findChild(a, "network_0").selected);
        compare(findChild(a, "network_0").iconName, "signal_wifi_4_bar", "by signal");
        compare(findChild(a, "network_1").iconName, "network_wifi_2_bar");
        verify(findChild(a, "networkForget_0").visible, "a saved network can be forgotten");
        verify(!findChild(a, "networkForget_1").visible);

        mouseClick(findChild(a, "network_0"));
        compare(b.calls, ["disconnect:Home"], "the connected one disconnects");
        mouseClick(findChild(a, "networkForget_0"));
        compare(b.calls[1], "forget:Home");
        mouseClick(findChild(a, "network_1"));
        compare(b.calls[2], "connect:Cafe", "an open one connects");

        // a secured network asks for its password, under it
        const office = findChild(a, "network_2");
        mouseClick(office);
        waitForRendering(a);
        const boxes = [];
        const walk = it => { if (it.objectName === "networkPasswordBox" && it.visible) boxes.push(it); for (const c of it.children) walk(c); };
        walk(a);
        compare(boxes.length, 1, "one password box");
        const field = findChild(boxes[0], "networkPassword");
        tryVerify(() => field.activeFocus, 1000, "focused");
        verify(!findChild(boxes[0], "networkPasswordConnect").enabled, "nothing typed: no Connect");
        for (const c of "hunter22") keyClick(c);
        keyClick(Qt.Key_Return);
        compare(b.calls[b.calls.length - 1], "password:Office:hunter22");
        compare(field.text, "", "not kept");
        waitForRendering(a);
        verify(!boxes[0].visible);
        mouseClick(office);
        waitForRendering(a);
        keyClick(Qt.Key_Escape);
        compare(b.calls[b.calls.length - 1], "cancel");

        compare(findChild(a, "networkWired_0").text, "Not connected");
        verify(findChild(a, "setting_network.ethernet").visible);

        mouseClick(findChild(a, "networkWifiSwitch"));
        compare(b.calls[b.calls.length - 1], "wifi:false");
        waitForRendering(a);
        verify(!findChild(a, "network_0"), "off: no networks");
        compare(findChild(a, "networkWifi").supportingText, "Off");

        b.wifiEnabled = true;
        b.networks = [];
        waitForRendering(a);
        verify(findChild(a, "networkSearching").visible, "on, nothing yet: looking");

        b.wifiAvailable = false;
        waitForRendering(a);
        verify(!findChild(a, "networkWifi").enabled, "no Wi-Fi device: nothing to switch");
        b.wired = [];
        waitForRendering(a);
        verify(!findChild(a, "setting_network.ethernet").visible, "no wired device: no Ethernet group");
        b.available = false;
        waitForRendering(a);
        verify(findChild(a, "networkUnavailable").visible);
    }

    function test_network_error_shows() {
        const t = make("network", networkComp);
        const n = t.b.networks.slice();
        n[1] = Object.assign({}, n[1], { error: "Could not connect" });
        n[2] = Object.assign({}, n[2], { busy: true });
        t.b.networks = n;
        waitForRendering(t.a);
        compare(findChild(t.a, "network_1").supportingText, "Could not connect");
        compare(findChild(t.a, "network_2").supportingText, "Connecting…");
    }

    function test_bluetooth() {
        const t = make("bluetooth", bluetoothComp);
        const a = t.a, b = t.b;
        verify(findChild(a, "bluetoothSwitch").checked);
        const buds = findChild(a, "bluetooth_paired_0");
        compare(buds.text, "Buds");
        compare(buds.supportingText, "Connected, battery 80%");
        compare(buds.iconName, "headphones");
        verify(buds.selected);
        compare(findChild(a, "bluetooth_paired_1").supportingText, "Not connected");
        compare(findChild(a, "bluetooth_paired_1").iconName, "mouse");
        const speaker = findChild(a, "bluetooth_available_0");
        compare(speaker.text, "Speaker");
        compare(speaker.iconName, "speaker");
        verify(!findChild(speaker, "bluetoothForget_0").visible, "not paired: nothing to forget");
        verify(!findChild(a, "bluetoothEmpty_paired").visible);

        mouseClick(buds);
        compare(b.calls, ["toggle:AA"]);
        mouseClick(speaker);
        compare(b.calls[1], "toggle:CC");
        mouseClick(findChild(findChild(a, "bluetooth_paired_1"), "bluetoothForget_1"));
        compare(b.calls[2], "forget:BB");

        const d = b.devices.slice();
        d[2] = Object.assign({}, d[2], { busy: true });
        b.devices = d;
        waitForRendering(a);
        compare(findChild(a, "bluetooth_available_0").supportingText, "Pairing…");
        verify(!findChild(a, "bluetooth_available_0").enabled, "busy: no clicks");

        b.devices = [];
        waitForRendering(a);
        compare(findChild(a, "bluetoothEmpty_available").text, "Looking for devices…");
        verify(findChild(a, "bluetoothEmpty_paired").visible);

        mouseClick(findChild(a, "bluetoothSwitch"));
        compare(b.calls[b.calls.length - 1], "enabled:false");
        waitForRendering(a);
        verify(!findChild(a, "setting_bluetooth.paired"), "off: no lists");
        b.available = false;
        waitForRendering(a);
        compare(findChild(a, "bluetoothSwitchRow").supportingText, "No Bluetooth adapter");
        verify(!findChild(a, "bluetoothSwitchRow").enabled);
    }

    function test_search_finds_them() {
        const keys = q => Model.search(q, Pages.pages, Schema.schema, Pages.hints).map(h => h.page + "/" + h.key);
        compare(keys("wi-fi")[0], "network/network.wifi");
        verify(keys("password").indexOf("network/network.wifi") >= 0, "beside the polkit agent's passwords");
        compare(keys("ethernet")[0], "network/network.ethernet");
        compare(keys("bluetooth")[0], "bluetooth/");
        compare(keys("add device")[0], "bluetooth/bluetooth.available");
        verify(keys("pair").slice(0, 2).indexOf("bluetooth/bluetooth.available") >= 0);
        const t = make("wallpaper", bluetoothComp);
        verify(!findChild(t.a, "bluetoothSwitch"), "views load only on their page");
        t.a.openPage("bluetooth", "bluetooth.paired");
        waitForRendering(t.a);
        verify(t.a.findRow("bluetooth.paired"), "a search result's group is found");
    }

    function test_without_backends() {
        const s = createTemporaryObject(storeComp, root);
        const a = createTemporaryObject(appComp, root, { store: s });
        a.openPage("network");
        waitForRendering(a);
        verify(findChild(a, "networkUnavailable").visible);
        a.openPage("bluetooth");
        waitForRendering(a);
        compare(findChild(a, "bluetoothSwitchRow").supportingText, "No Bluetooth adapter");
    }
}
