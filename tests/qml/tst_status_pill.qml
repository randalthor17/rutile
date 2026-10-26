import QtQuick
import QtTest
import qs.common
import qs.components
import qs.bar
import "../qs/bar/StatusIcons.js" as StatusIcons

TestCase {
    id: root
    name: "StatusPill"
    width: 400
    height: 200
    visible: true
    when: windowShown

    Component {
        id: fakeComp
        QtObject {
            property bool volumeAvailable: true
            property real volume: 0.7
            property bool muted: false
            property bool wifiAvailable: true
            property bool wifiEnabled: true
            property string wifiName: "Home"
            property real wifiSignal: 0.8
            property bool wiredConnected: false
            property bool batteryAvailable: true
            property real battery: 0.82
            property bool charging: false
        }
    }
    Component { id: pillComp; StatusPill {} }
    Component { id: spyComp; SignalSpy {} }

    function make(props) {
        var backend = createTemporaryObject(fakeComp, root, props || {});
        var pill = createTemporaryObject(pillComp, root, { backend: backend, x: 20, y: 20 });
        waitForRendering(pill);
        return { pill: pill, backend: backend };
    }

    function test_network_icon() {
        var b = { wifiAvailable: true, wifiEnabled: true, wifiName: "Home", wifiSignal: 0.8, wiredConnected: false };
        compare(StatusIcons.network(b), "network_wifi");
        b.wifiSignal = 0.6; compare(StatusIcons.network(b), "network_wifi_3_bar");
        b.wifiSignal = 0.3; compare(StatusIcons.network(b), "network_wifi_2_bar");
        b.wifiSignal = 0.1; compare(StatusIcons.network(b), "network_wifi_1_bar");
        b.wifiName = ""; compare(StatusIcons.network(b), "signal_wifi_0_bar", "on, not connected");
        b.wifiEnabled = false; compare(StatusIcons.network(b), "wifi_off");
        b.wifiAvailable = false; compare(StatusIcons.network(b), "", "no Wi-Fi, no cable: nothing");
        b.wiredConnected = true; compare(StatusIcons.network(b), "settings_ethernet", "a cable wins");
    }

    function test_volume_icon() {
        var b = { volumeAvailable: true, volume: 0.7, muted: false };
        compare(StatusIcons.volume(b), "volume_up");
        b.volume = 0.3; compare(StatusIcons.volume(b), "volume_down");
        b.volume = 0; compare(StatusIcons.volume(b), "volume_off");
        b.volume = 0.5; b.muted = true; compare(StatusIcons.volume(b), "volume_off");
        b.volumeAvailable = false; compare(StatusIcons.volume(b), "");
    }

    function test_battery_icon() {
        var b = { batteryAvailable: true, battery: 0.82, charging: false };
        compare(StatusIcons.battery(b), "battery_5_bar");
        b.battery = 0.97; compare(StatusIcons.battery(b), "battery_full");
        b.battery = 0.05; compare(StatusIcons.battery(b), "battery_0_bar");
        b.battery = 0.9; compare(StatusIcons.battery(b), "battery_6_bar");
        b.charging = true; compare(StatusIcons.battery(b), "battery_charging_90");
        b.battery = 0.55; compare(StatusIcons.battery(b), "battery_charging_50");
        b.battery = 0.1; compare(StatusIcons.battery(b), "battery_charging_20");
        b.battery = 0.99; compare(StatusIcons.battery(b), "battery_charging_full");
        b.batteryAvailable = false; compare(StatusIcons.battery(b), "");
    }

    function test_pill_shows_what_the_backend_has() {
        var t = make();
        var icons = findChild(t.pill, "statusIcons");
        compare(icons.name, "network_wifi volume_up battery_5_bar", "one Icon, three ligatures");
        compare(icons.fill, 1);
        compare(findChild(t.pill, "statusBatteryText").text, "82%");
        verify(icons.width > 2.5 * icons.size, "sized to all three glyphs, not one");
        var wide = t.pill.width;
        t.backend.batteryAvailable = false;
        compare(icons.name, "network_wifi volume_up");
        verify(!findChild(t.pill, "statusBatteryText").visible);
        tryVerify(function () { return t.pill.width < wide; }, 1000, "the pill shrinks to what it shows");
        t.backend.muted = true;
        compare(icons.name, "network_wifi volume_off");
        t.backend.volumeAvailable = false;
        t.backend.wifiAvailable = false;
        compare(icons.name, "tune", "nothing to report: still something to click");
        compare(icons.fill, 0);
    }

    function test_click_and_open_state() {
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.pill, signalName: "clicked" });
        var closed = String(t.pill.color);     // a copy: reading a color property gives a live reference
        compare(t.pill.height, Spacing.xl);
        compare(findChild(t.pill, "statusIcons").size, Spacing.lg);
        mouseClick(t.pill, t.pill.width / 2, t.pill.height / 2);
        compare(spy.count, 1);
        t.pill.open = true;
        tryVerify(function () { return Qt.colorEqual(t.pill.color, Colors.secondaryContainer); }, 2000);
        verify(closed !== String(Colors.secondaryContainer));
        compare(t.pill.color.a, 1, "a container while open");
        compare(t.pill.contentColor, Colors.secondaryContainerOn);
        t.pill.open = false;
        tryVerify(function () { return Qt.colorEqual(t.pill.color, Colors.surfaceContainer); }, 2000,
                  "closed: a tonal container");
    }
}
