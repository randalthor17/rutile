import QtQuick
import QtTest
import qs.common
import qs.components
import qs.quicksettings
import "../qs/services/BrightnessCtl.js" as Ctl
import "../qs/quicksettings/PowerActions.js" as PowerActions

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
            function powerAction(id) { log("power " + id); }
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
        // a backend that arrives after creation (bound through the window) is refreshed too
        var late = createTemporaryObject(panelComp, root, { backend: null });
        var b = createTemporaryObject(fakeComp, root);
        late.backend = b;
        compare(b.calls[0], "refresh");
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

    function test_clicks_inside_do_not_count_as_losing_focus() {
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "windowFocusLost" });
        root.Window.window.requestActivate();
        tryVerify(function () { return t.panel.windowActive; }, 2000);
        var v = findChild(t.panel, "qsVolume");
        mouseClick(v, v.width * 0.6, v.height / 2);
        verify(v.activeFocus, "the slider took the item focus");
        clickItem(tile(t.panel, "dark"));
        compare(spy.count, 0, "focus moving inside the panel does not close it");
        // Another window taking focus is tested under sway (tools/qtws.py test-wayland): the offscreen
        // platform does not move window activation.
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
        var spies = ["settingsRequested", "soundSettingsRequested"].map(
            n => createTemporaryObject(spyComp, root, { target: t.panel, signalName: n }));
        clickItem(findChild(t.panel, "qsSettings"));
        clickItem(findChild(t.panel, "qsSoundSettings"));
        spies.forEach(s => compare(s.count, 1, s.signalName));
        var dark = findChild(t.panel, "qsDarkButton");
        verify(dark.checked);
        clickItem(dark);
        compare(t.backend.calls[t.backend.calls.length - 1], "dark false");
    }

    function test_power_button_opens_the_power_menu() {
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "powerActionTaken" });
        var button = findChild(t.panel, "qsPower");
        compare(findChild(t.panel, "qsPowerChevron").name, "expand_more", "power and a chevron");
        compare(findChild(t.panel, "qsPowerMenu").item, null, "the menu exists only while open");
        clickItem(button);
        verify(t.panel.powerMenuOpen);
        compare(findChild(t.panel, "qsPowerChevron").name, "expand_less");
        var menu = findChild(t.panel, "qsPowerMenu").item;
        verify(menu);
        ["lock", "logout", "reboot", "poweroff"].forEach(id => verify(findChild(menu, "qsPower_" + id), id));
        compare(findChild(menu, "qsPower_lock").position, "first");
        compare(findChild(menu, "qsPower_poweroff").position, "last");
        compare(t.backend.calls.filter(c => c.indexOf("power") === 0).length, 0, "opening the menu does nothing yet");
        clickItem(button);
        verify(!t.panel.powerMenuOpen, "the button closes it again");
        clickItem(button);
        clickItem(findChild(findChild(t.panel, "qsPowerMenu").item, "qsPower_reboot"));
        compare(t.backend.calls[t.backend.calls.length - 1], "power reboot");
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], "reboot");
        verify(!t.panel.powerMenuOpen, "choosing closes the menu");
        // edit mode hides the button and the menu
        clickItem(button);
        t.panel.editMode = true;
        verify(!button.visible);
        compare(findChild(t.panel, "qsPowerMenu").item, null);
    }

    function test_power_commands() {
        compare(PowerActions.actions.map(a => a.id).join(), "lock,logout,reboot,poweroff");
        compare(PowerActions.command("lock").join(" "), "loginctl lock-session");
        compare(PowerActions.command("logout").join(" "), "niri msg action quit --skip-confirmation");
        compare(PowerActions.command("reboot").join(" "), "systemctl reboot");
        compare(PowerActions.command("poweroff").join(" "), "systemctl poweroff");
        compare(PowerActions.command("format-disk"), null);
    }

    function test_panel_grows_in_and_shrinks_away() {
        var fresh = createTemporaryObject(panelComp, root, { backend: createTemporaryObject(fakeComp, root) });
        verify(fresh.scale < 0.9, "starts small");
        tryCompare(fresh, "scale", 1, 2000, "and grows in");
        var t = make();
        var hidden = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "hidden" });
        tryCompare(t.panel, "scale", 1, 2000, "grown in");
        compare(t.panel.opacity, 1);
        verify(t.panel.enabled);
        t.panel.shown = false;
        verify(!t.panel.enabled, "no input while it goes away");
        tryVerify(function () { return t.panel.scale < 0.9; }, 2000, "shrinks toward the corner");
        tryCompare(hidden, "count", 1, 2000);
        compare(t.panel.opacity, 0);
        compare(t.panel.transformOrigin, Item.TopRight, "toward the status pill");
        // shown again before it is gone: it grows back and never reports hidden
        var u = make();
        var spy = createTemporaryObject(spyComp, root, { target: u.panel, signalName: "hidden" });
        tryCompare(u.panel, "scale", 1, 2000);
        u.panel.shown = false;
        wait(50);
        u.panel.shown = true;
        tryCompare(u.panel, "scale", 1, 2000);
        compare(spy.count, 0);
    }

    function test_edit_mode_removes_tiles() {
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "tilesEdited" });
        compare(findChild(t.panel, "qsEditTiles").iconName, "edit", "a pen");
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
