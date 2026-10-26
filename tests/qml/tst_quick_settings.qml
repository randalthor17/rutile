import QtQuick
import QtTest
import qs.common
import qs.components
import qs.quicksettings
import "../qs/services/BrightnessCtl.js" as Ctl

TestCase {
    id: root
    name: "QuickSettings"
    width: 600
    height: 900
    visible: true
    when: windowShown

    // The backend interface QuickSettingsPanel uses, recording what was asked.
    Component {
        id: fakeComp
        QtObject {
            property bool brightnessAvailable: true
            property real brightness: 0.5
            property bool volumeAvailable: true
            property real volume: 0.4
            property bool muted: false
            property bool micAvailable: true
            property bool micMuted: false
            property bool wifiAvailable: true
            property bool wifiEnabled: true
            property string wifiName: "Home"
            property bool bluetoothAvailable: true
            property bool bluetoothEnabled: false
            property string bluetoothDevice: ""
            property bool darkTheme: true
            property var calls: []
            function log(c) { calls = calls.concat([c]); }
            function setBrightness(v) { log("brightness " + v.toFixed(2)); }
            function setVolume(v) { log("volume " + v.toFixed(2)); }
            function setMicMuted(m) { log("micMuted " + m); }
            function setWifiEnabled(b) { log("wifi " + b); }
            function setBluetoothEnabled(b) { log("bluetooth " + b); }
            function setDarkTheme(b) { log("dark " + b); }
            function setAirplaneMode(b) { log("airplane " + b); }
            function refresh() { log("refresh"); }
        }
    }
    Component {
        id: panelComp
        QuickSettingsPanel {}
    }

    function make(props) {
        var backend = createTemporaryObject(fakeComp, root, props || {});
        var panel = createTemporaryObject(panelComp, root, { backend: backend });
        waitForRendering(panel);
        return { panel: panel, backend: backend };
    }

    function tile(panel, id) { return findChild(panel, "qsTile_" + id); }

    function clickItem(item) {
        mouseClick(item, item.width / 2, item.height / 2);
    }

    function test_opening_refreshes_the_backend() {
        var t = make();
        compare(t.backend.calls[0], "refresh");
    }

    function test_tiles_show_the_backend_state() {
        var t = make();
        var wifi = tile(t.panel, "wifi");
        verify(wifi.active);
        compare(wifi.secondaryText, "Home");
        compare(wifi.iconName, "wifi");
        verify(!wifi.iconOnly, "Wi-Fi is a large tile");
        var bt = tile(t.panel, "bluetooth");
        verify(!bt.active);
        compare(bt.secondaryText, "Off");
        compare(bt.iconName, "bluetooth_disabled");
        verify(tile(t.panel, "mic").active);
        verify(tile(t.panel, "mic").iconOnly);
        verify(tile(t.panel, "dark").active);
        verify(!tile(t.panel, "airplane").active);
        t.backend.bluetoothEnabled = true;
        t.backend.bluetoothDevice = "Pixel Buds";
        compare(bt.secondaryText, "Pixel Buds");
        t.backend.wifiName = "";
        compare(wifi.secondaryText, "On");
        t.backend.wifiEnabled = false;
        compare(wifi.secondaryText, "Off");
        compare(wifi.iconName, "wifi_off");
        t.backend.micMuted = true;
        verify(!tile(t.panel, "mic").active);
        compare(tile(t.panel, "mic").secondaryText, "Muted");
    }

    function test_airplane_mode_is_on_when_every_radio_is_off() {
        var t = make({ wifiEnabled: false, bluetoothEnabled: false });
        verify(tile(t.panel, "airplane").active);
        t.backend.bluetoothEnabled = true;
        verify(!tile(t.panel, "airplane").active);
        // a missing radio does not keep airplane mode off
        t.backend.bluetoothAvailable = false;
        verify(tile(t.panel, "airplane").active);
        t.backend.wifiAvailable = false;
        verify(!tile(t.panel, "airplane").available, "no radios: nothing to turn off");
        // a radio whose hardware is gone does not count, whatever its last state
        var u = make({ wifiAvailable: false, wifiEnabled: true, bluetoothEnabled: false });
        verify(tile(u.panel, "airplane").active);
    }

    function test_missing_hardware_makes_tiles_unavailable() {
        var t = make({ wifiAvailable: false, micAvailable: false });
        verify(!tile(t.panel, "wifi").available);
        compare(tile(t.panel, "wifi").secondaryText, "Unavailable");
        verify(!tile(t.panel, "mic").available);
        verify(tile(t.panel, "bluetooth").available);
    }

    function test_toggles_ask_the_backend_and_wait_for_it() {
        var t = make();
        var wifi = tile(t.panel, "wifi");
        // a dual-target tile toggles from its icon, on the leading side
        mouseClick(wifi, ControlSpec.tileSpec.iconSize, wifi.height / 2);
        compare(t.backend.calls[t.backend.calls.length - 1], "wifi false");
        verify(wifi.active, "controlled: stays on until the backend says otherwise");
        t.backend.wifiEnabled = false;
        verify(!wifi.active);
        clickItem(tile(t.panel, "mic"));
        compare(t.backend.calls[t.backend.calls.length - 1], "micMuted true");
        clickItem(tile(t.panel, "dark"));
        compare(t.backend.calls[t.backend.calls.length - 1], "dark false");
        clickItem(tile(t.panel, "airplane"));
        compare(t.backend.calls[t.backend.calls.length - 1], "airplane false", "Wi-Fi and Bluetooth are off now");
        t.backend.wifiEnabled = true;
        clickItem(tile(t.panel, "airplane"));
        compare(t.backend.calls[t.backend.calls.length - 1], "airplane true");
    }

    function test_dual_target_body_opens_details() {
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "detailsRequested" });
        var bt = tile(t.panel, "bluetooth");
        mouseClick(bt, bt.width - 20, bt.height / 2);
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], "bluetooth");
        verify(t.backend.calls.indexOf("bluetooth true") < 0, "the body does not toggle");
    }

    Component { id: spyComp; SignalSpy {} }

    function test_sliders_follow_the_backend_and_report_moves() {
        var t = make();
        var b = findChild(t.panel, "qsBrightness");
        var v = findChild(t.panel, "qsVolume");
        compare(b.value, 0.5);
        compare(v.value, 0.4);
        t.backend.brightness = 0.8;
        compare(b.value, 0.8);
        // drag: the slider follows the pointer, the backend is told
        mousePress(b, b.width * 0.2, b.height / 2);
        mouseMove(b, b.width * 0.3, b.height / 2);
        verify(t.backend.calls.some(c => c.indexOf("brightness ") === 0));
        t.backend.brightness = 0.9;     // a late report from the backend does not yank the handle
        verify(Math.abs(b.value - 0.3) < 0.05, b.value);
        mouseRelease(b, b.width * 0.3, b.height / 2);
        compare(b.value, 0.9, "after release the slider follows the backend again");
        t.backend.brightness = 0.6;
        compare(b.value, 0.6);
        // keyboard
        v.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(t.backend.calls[t.backend.calls.length - 1], "volume 0.41");
        t.backend.volume = 0.7;
        compare(v.value, 0.7);
        t.backend.muted = true;
        compare(v.value, 0, "muted shows as empty");
        compare(v.endIcon, "music_off");
    }

    function test_rows_hide_without_brightness_or_audio() {
        var t = make({ brightnessAvailable: false, volumeAvailable: false });
        verify(!findChild(t.panel, "qsBrightness").visible);
        verify(!findChild(t.panel, "qsVolume").visible);
        var withBoth = make();
        verify(t.panel.height < withBoth.panel.height);
    }

    function test_header_buttons() {
        var t = make();
        var spies = ["settingsRequested", "powerRequested", "soundSettingsRequested"].map(
            n => createTemporaryObject(spyComp, root, { target: t.panel, signalName: n }));
        clickItem(findChild(t.panel, "qsSettings"));
        clickItem(findChild(t.panel, "qsPower"));
        clickItem(findChild(t.panel, "qsSoundSettings"));
        spies.forEach(s => compare(s.count, 1, s.signalName));
        var dark = findChild(t.panel, "qsDarkButton");
        verify(dark.checked);
        clickItem(dark);
        compare(t.backend.calls[t.backend.calls.length - 1], "dark false");
    }

    function test_edit_mode_removes_tiles() {
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "tilesEdited" });
        clickItem(findChild(t.panel, "qsEditTiles"));
        verify(t.panel.editMode);
        verify(!findChild(t.panel, "qsBrightness").visible, "sliders make way for editing");
        var remove = findChild(t.panel, "qsRemove");
        verify(remove.visible);
        verify(!remove.enabled, "nothing selected yet");
        clickItem(tile(t.panel, "mic"));
        compare(t.backend.calls.indexOf("micMuted true"), -1, "editing does not toggle");
        verify(remove.enabled);
        clickItem(remove);
        compare(t.panel.tiles.map(x => x.id).join(), "wifi,bluetooth,dark,airplane");
        compare(spy.count, 1);
        clickItem(findChild(t.panel, "qsEditDone"));
        verify(!t.panel.editMode);
    }

    // ---- brightnessctl ----
    function test_brightnessctl_output_is_parsed() {
        compare(JSON.stringify(Ctl.parse("intel_backlight,backlight,512,48%,1060\n")),
                JSON.stringify({ device: "intel_backlight", current: 512, max: 1060 }));
        compare(Ctl.parse("input1::numlock,leds,0,0%,1\namdgpu_bl0,backlight,10,4%,255").device, "amdgpu_bl0",
                "skips other classes");
        compare(Ctl.parse("amdgpu_bl0,backlight,10,4%,255").device, "amdgpu_bl0");
        compare(Ctl.parse(""), null);
        compare(Ctl.parse("Failed to read any devices of class 'backlight'."), null);
        compare(Ctl.parse("x,backlight,5,1%,0"), null, "a zero maximum is no device");
        compare(Ctl.parse("input1::numlock,leds,0,0%,1"), null, "LEDs are not backlights");
    }

    function test_brightnessctl_commands() {
        compare(Ctl.rawFor(0.5, 1060), 530);
        compare(Ctl.rawFor(0, 1060), 1, "never fully off");
        compare(Ctl.rawFor(1.2, 255), 255);
        compare(Ctl.readCommand().join(" "), "brightnessctl -m -c backlight info");
        compare(Ctl.setCommand("intel_backlight", 530).join(" "),
                "brightnessctl -m -c backlight -d intel_backlight set 530");
    }
}
