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
            property var calls: []
            function setVolume(v) { calls = calls.concat(["volume " + v.toFixed(2)]); volume = v; muted = false; }
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

    // Scrolls over the middle of glyph `i` (of `n` shown) in the pill's icons.
    function wheelOver(pill, i, n, notches) {
        var icons = findChild(pill, "statusIcons");
        var p = icons.mapToItem(pill, (i + 0.5) * icons.width / n, icons.height / 2);
        mouseWheel(pill, p.x, p.y, 0, 120 * notches);
    }

    function test_scrolling_over_the_volume_glyph_changes_the_volume() {
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.pill, signalName: "clicked" });
        wheelOver(t.pill, 1, 3, 1);
        compare(t.backend.calls.join(), "volume 0.75", "up a notch: 5%");
        wheelOver(t.pill, 1, 3, -2);
        compare(t.backend.calls[1], "volume 0.65", "down two notches");
        wheelOver(t.pill, 0, 3, 1);
        wheelOver(t.pill, 2, 3, 1);
        compare(t.backend.calls.length, 2, "the network and battery glyphs do not scroll the volume");
        compare(spy.count, 0, "scrolling does not open the panel");
        mouseClick(t.pill, t.pill.width / 2, t.pill.height / 2);
        compare(spy.count, 1, "a click over the volume glyph still opens it");
        // clamped to 0..1
        t.backend.volume = 0.98;
        wheelOver(t.pill, 1, 3, 1);
        compare(t.backend.calls[2], "volume 1.00");
        // muted counts as 0: up unmutes from the bottom, down stays at 0
        t.backend.muted = true;
        wheelOver(t.pill, 1, 3, -1);
        compare(t.backend.calls[3], "volume 0.00");
        t.backend.muted = true;
        wheelOver(t.pill, 1, 3, 1);
        compare(t.backend.calls[4], "volume 0.05");
        // QtTest's wheel comes from a mouse; on niri Qt reports it as a touchpad, which WheelHandler declines by default
        var wheel = findChild(t.pill, "statusVolumeWheel");
        compare(wheel.acceptedDevices & PointerDevice.TouchPad, PointerDevice.TouchPad);
    }

    function test_volume_glyph_moves_with_the_others() {
        var t = make({ wifiAvailable: false, batteryAvailable: false });
        wheelOver(t.pill, 0, 1, 1);
        compare(t.backend.calls.join(), "volume 0.75", "the only glyph");
        t.backend.wifiAvailable = true;
        waitForRendering(t.pill);       // the row relayouts on the next polish
        wheelOver(t.pill, 0, 2, 1);
        compare(t.backend.calls.length, 1, "network first now");
        wheelOver(t.pill, 1, 2, 1);
        compare(t.backend.calls[1], "volume 0.80");
        t.backend.volumeAvailable = false;
        verify(!findChild(t.pill, "statusVolumeZone").visible, "no audio: nothing to scroll");
        wheelOver(t.pill, 0, 1, 1);
        compare(t.backend.calls.length, 2);
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
