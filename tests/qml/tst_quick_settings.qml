import QtQuick
import QtTest
import qs.common
import qs.components
import qs.quicksettings
import "../qs/services/BrightnessCtl.js" as Ctl
import "../qs/power/PowerActions.js" as PowerActions
import "../qs/quicksettings/Controls.js" as Controls
import "../qs/quicksettings/Details.js" as Details
import "../qs/services/NightLight.js" as NightLight

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
            property bool dnd: false
            property bool powerSaverAvailable: true
            property bool nightLightAvailable: true
            property bool nightLight: false
            property bool nightLightScheduled: false
            property bool powerSaver: false
            property int nightLightTemperature: 4000
            property string powerProfile: "balanced"
            property bool performanceAvailable: true
            property var wifiNetworks: [
                { name: "Cafe", signal: 0.9, secure: false, psk: false, connected: false, known: false, busy: false },
                { name: "Home", signal: 0.4, secure: true, psk: true, connected: true, known: true, busy: false },
                { name: "Neighbour", signal: 0.6, secure: true, psk: true, connected: false, known: false, busy: false },
                { name: "Work", signal: 0.3, secure: true, psk: false, connected: false, known: false, busy: false }
            ]
            property var bluetoothDevices: [
                { address: "AA", name: "Mouse", named: true, icon: "input-mouse", connected: false, paired: true, busy: false, battery: -1 },
                { address: "BB", name: "Buds", named: true, icon: "audio-headset", connected: true, paired: true, busy: false, battery: 0.8 }
            ]
            property var calls: []
            function log(c) { calls = calls.concat([c]); }
            function setBrightness(v) { log("brightness " + v.toFixed(2)); }
            function setVolume(v) { log("volume " + v.toFixed(2)); }
            function setMicMuted(m) { log("micMuted " + m); }
            function setWifiEnabled(b) { log("wifi " + b); }
            function setBluetoothEnabled(b) { log("bluetooth " + b); }
            function setDarkTheme(b) { log("dark " + b); }
            function setAirplaneMode(b) { log("airplane " + b); }
            function setDnd(b) { log("dnd " + b); }
            function setPowerSaver(b) { log("powerSaver " + b); }
            function setNightLight(b) { log("nightLight " + b); }
            function setNightLightTemperature(k) { log("temperature " + k); nightLightTemperature = k; }
            function setNightLightScheduled(b) { log("schedule " + b); nightLightScheduled = b; }
            function setPowerProfile(p) { log("profile " + p); powerProfile = p; }
            function connectWifi(n, psk) { log("connectWifi " + n + (psk ? " " + psk : "")); }
            function disconnectWifi(n) { log("disconnectWifi " + n); }
            function forgetWifi(n) { log("forgetWifi " + n); }
            function setWifiScanning(b) { log("wifiScanning " + b); }
            property bool hiddenJoining: false
            property string hiddenName: ""
            function joinHiddenWifi(n, p) { log("joinHiddenWifi " + n + (p ? " " + p : "")); }
            function connectBluetooth(a) { log("connectBluetooth " + a); }
            function disconnectBluetooth(a) { log("disconnectBluetooth " + a); }
            function setBluetoothDiscovering(b) { log("discovering " + b); }
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
    // the Columns an item is in have placed it (a click before then lands where it was)
    function laidOut(item) {
        for (var it = item; it; it = it.parent) waitForItemPolished(it);
    }

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

    function openDetails(t, id) {
        tryCompare(t.panel, "appearProgress", 1, 2000);
        var x = tile(t.panel, id);
        mouseClick(x, x.width - 20, x.height / 2);
        compare(t.panel.details, id);
        waitForRendering(t.panel);
    }
    function row(panel, key) { return findChild(panel, "qsDetailsRow_" + key); }
    function rowY(panel, key) { return row(panel, key).mapToItem(panel, 0, 0).y; }

    function test_wifi_details_list_and_connect() {
        var t = make();
        openDetails(t, "wifi");
        verify(t.backend.calls.indexOf("wifiScanning true") >= 0, "scans while open");
        verify(!findChild(t.panel, "qsBrightness").visible, "the page replaces the rest");
        verify(!tile(t.panel, "wifi").visible);
        verify(findChild(t.panel, "qsDetailsSwitch").checked);
        compare(row(t.panel, "Home").supportingText, "Connected");
        verify(rowY(t.panel, "Home") < rowY(t.panel, "Cafe"), "the connected first");
        verify(rowY(t.panel, "Cafe") < rowY(t.panel, "Neighbour"), "then by signal");
        clickItem(row(t.panel, "Cafe"));
        compare(t.backend.calls[t.backend.calls.length - 1], "connectWifi Cafe", "an open one connects");
        verify(!findChild(t.panel, "qsForget_Cafe").visible, "only a saved network is forgotten");
        clickItem(findChild(t.panel, "qsForget_Home"));
        compare(t.backend.calls[t.backend.calls.length - 1], "forgetWifi Home", "the button, not the row");
        clickItem(row(t.panel, "Home"));
        compare(t.backend.calls[t.backend.calls.length - 1], "disconnectWifi Home");
        var n = t.backend.calls.length;
        clickItem(row(t.panel, "Work"));
        compare(t.backend.calls.length, n, "enterprise sign-in: nothing to do here");
        verify(!findChild(t.panel, "qsPassword_Work").visible, "nor a password to ask for");
        // a secured one asks for its password, under it
        clickItem(row(t.panel, "Neighbour"));
        var field = findChild(t.panel, "qsPassword_Neighbour");
        verify(field.visible);
        tryVerify(() => field.focused, 1000, "the field takes the keys");
        keyClick(Qt.Key_Return);
        compare(t.backend.calls.length, n, "no empty password");
        for (const c of "s3cret") keyClick(c);
        compare(field.text, "s3cret");
        keyClick(Qt.Key_Return);
        compare(t.backend.calls[t.backend.calls.length - 1], "connectWifi Neighbour s3cret");
        verify(!field.visible);
        // back: scanning stops, the panel returns
        clickItem(findChild(t.panel, "qsDetailsBack"));
        compare(t.panel.details, "");
        compare(t.backend.calls[t.backend.calls.length - 1], "wifiScanning false");
        verify(findChild(t.panel, "qsBrightness").visible);
    }

    function test_wifi_hidden_network() {
        var t = make();
        openDetails(t, "wifi");
        var item = findChild(t.panel, "qsHiddenNetwork");
        var name = findChild(t.panel, "qsHiddenName");
        var password = findChild(t.panel, "qsHiddenPassword");
        verify(item.visible);
        verify(!name.visible && !password.visible, "asks nothing until chosen");
        clickItem(row(t.panel, "Neighbour"));
        clickItem(item);
        verify(name.visible && password.visible);
        verify(!findChild(t.panel, "qsPassword_Neighbour").visible, "one question at a time");
        tryVerify(() => name.focused, 1000, "the name takes the keys");
        var n = t.backend.calls.length;
        keyClick(Qt.Key_Return);
        compare(t.backend.calls.length, n, "no name: nothing joined");
        for (const c of "Lab 5") keyClick(c);
        keyClick(Qt.Key_Return);
        tryVerify(() => password.focused, 1000, "Enter goes on to the password");
        for (const c of "pw") keyClick(c);
        keyClick(Qt.Key_Return);
        compare(t.backend.calls[t.backend.calls.length - 1], "joinHiddenWifi Lab 5 pw");
        verify(!name.visible, "the form closes");
        // an open one: no password; Escape cancels
        clickItem(item);
        compare(name.text, "", "a fresh form");
        for (const c of "Open") keyClick(c);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Return);
        compare(t.backend.calls[t.backend.calls.length - 1], "joinHiddenWifi Open");
        clickItem(item);
        keyClick(Qt.Key_Escape);
        verify(!name.visible, "Escape cancels");
        t.backend.hiddenJoining = true;
        t.backend.hiddenName = "Lab 5";
        compare(item.supportingText, "Joining Lab 5…");
        t.backend.wifiEnabled = false;
        verify(!item.visible, "Wi-Fi off: nothing to join");
    }

    function test_wifi_switch_and_empty_page() {
        var t = make({ wifiEnabled: false, wifiNetworks: [] });
        openDetails(t, "wifi");
        compare(findChild(t.panel, "qsDetailsEmpty").text, "Turn on Wi-Fi to see networks");
        var sw = findChild(t.panel, "qsDetailsSwitch");
        clickItem(sw);
        compare(t.backend.calls[t.backend.calls.length - 1], "wifi true");
        t.backend.wifiEnabled = true;
        compare(findChild(t.panel, "qsDetailsEmpty").text, "Looking for networks…");
    }

    function test_bluetooth_details() {
        var t = make({ bluetoothEnabled: true });
        openDetails(t, "bluetooth");
        verify(t.backend.calls.indexOf("discovering true") >= 0);
        compare(row(t.panel, "BB").supportingText, "Connected · 80%");
        compare(row(t.panel, "BB").iconName, "headset_mic");
        verify(rowY(t.panel, "BB") < rowY(t.panel, "AA"), "the connected first");
        clickItem(row(t.panel, "AA"));
        compare(t.backend.calls[t.backend.calls.length - 1], "connectBluetooth AA");
        clickItem(row(t.panel, "BB"));
        compare(t.backend.calls[t.backend.calls.length - 1], "disconnectBluetooth BB");
        t.panel.details = "";
        compare(t.backend.calls[t.backend.calls.length - 1], "discovering false", "stops when the page goes");
    }

    function test_details_lists() {
        var nets = Details.networks([
            { name: "A", signal: 0.2, connected: false, known: true }, { name: "", signal: 1 },
            { name: "B", signal: 0.9, connected: false, known: false }, { name: "A", signal: 0.7, connected: false, known: true },
            null, { name: "C", signal: 0.1, connected: true, known: true }]);
        compare(nets.map(n => n.name + n.signal).join(), "C0.1,A0.7,B0.9", "connected, known, signal; strongest of a name");
        compare(Details.signalIcon(0.8), "network_wifi");
        compare(Details.signalIcon(0.5), "network_wifi_3_bar");
        compare(Details.signalIcon(0.3), "network_wifi_2_bar");
        compare(Details.signalIcon(0.1), "network_wifi_1_bar");
        compare(Details.networkStatus({ busy: true, connected: false }), "Connecting…");
        compare(Details.networkStatus({ busy: true, connected: true }), "Disconnecting…");
        compare(Details.networkStatus({ known: true }), "Saved");
        compare(Details.networkStatus({ secure: false }), "Open");
        compare(Details.networkAction({ busy: true, connected: true }), "");
        compare(Details.networkAction({ known: true, secure: true }), "connect");
        compare(Details.networkAction({ secure: true, psk: true }), "password");
        var devs = Details.devices([
            { address: "1", name: "1", named: false, paired: false, connected: false },
            { address: "2", name: "Zed", named: true, paired: false, connected: false },
            { address: "3", name: "Alpha", named: true, paired: true, connected: false },
            { address: "", name: "x" },
            { address: "4", name: "Mid", named: true, paired: true, connected: true }]);
        compare(devs.map(d => d.address).join(), "4,3,2,1", "connected, paired, named, by name");
        compare(Details.deviceIcon("input-keyboard"), "keyboard");
        compare(Details.deviceIcon("something-new"), "bluetooth");
        compare(Details.deviceStatus({ busy: true, paired: false }), "Pairing…");
        compare(Details.deviceStatus({ busy: true, paired: true }), "Connecting…");
        compare(Details.deviceStatus({ connected: true, battery: -1 }), "Connected");
        compare(Details.deviceStatus({ paired: false }), "Not paired");
        compare(Details.deviceAction({ busy: true }), "");
    }

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

    function test_power_button_asks_for_the_power_menu() {
        var t = make();
        var asked = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "powerMenuRequested" });
        compare(findChild(t.panel, "qsPowerChevron").name, "expand_more", "power and a chevron, as Googlebook");
        clickItem(findChild(t.panel, "qsPower"));
        compare(asked.count, 1, "the full-screen power menu is the shell's");
        t.panel.editMode = true;
        verify(!findChild(t.panel, "qsPower").visible, "no power button in edit mode");
    }

    function test_power_commands() {
        compare(PowerActions.actions.map(a => a.id).join(), "lock,suspend,logout,reboot,poweroff");
        compare(PowerActions.command("suspend").join(" "), "systemctl suspend");
        compare(PowerActions.command("lock"), null, "the shell locks itself");
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
        compare(t.panel.tiles.map(x => x.id).join(), "wifi,bluetooth,dark,airplane,dnd,nightLight");
        compare(spy.count, 1);
        clickItem(findChild(t.panel, "qsEditDone"));
        verify(!t.panel.editMode);
    }

    // ---- Night light and power modes (D108) ----
    function test_night_light_page() {
        var t = make({ nightLight: true });
        var asked = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "settingsPageRequested" });
        verify(tile(t.panel, "nightLight").dualTarget, "the tile has a details side");
        t.panel.details = "nightLight";
        var page = findChild(t.panel, "qsNightLightPage");
        tryVerify(() => page && page.visible);
        verify(!findChild(t.panel, "qsDetailsEmpty").visible, "no list, so no list's empty text");
        verify(!findChild(t.panel, "qsPowerPage").visible);
        verify(findChild(t.panel, "qsDetailsSwitch").checked, "its switch, as on the tile");
        var warmth = findChild(t.panel, "qsNightLightWarmth");
        laidOut(warmth);
        compare(warmth.value, 4000);
        compare(findChild(t.panel, "qsNightLightKelvin").text, "4000 K");
        // a drag saves once, when let go
        mousePress(warmth, warmth.width * 0.1, warmth.height / 2);
        mouseMove(warmth, warmth.width * 0.2, warmth.height / 2);
        mouseMove(warmth, warmth.width * 0.3, warmth.height / 2);
        wait(500);                                  // a pause mid-drag saves nothing yet
        compare(t.backend.calls.filter(c => c.startsWith("temperature")).length, 0, "not while held");
        mouseRelease(warmth, warmth.width * 0.3, warmth.height / 2);
        tryVerify(() => t.backend.calls.some(c => c.startsWith("temperature")), 2000);
        wait(400);
        var saved = t.backend.calls.filter(c => c.startsWith("temperature"));
        compare(saved.length, 1, "once, after the drag");
        verify(t.backend.nightLightTemperature < 4000 && t.backend.nightLightTemperature % 100 === 0,
               "warmer, in steps of 100: " + t.backend.nightLightTemperature);
        // a keyboard step saves at once
        warmth.forceActiveFocus();
        keyClick(Qt.Key_Right);
        tryCompare(t.backend, "nightLightTemperature", Number(saved[0].split(" ")[1]) + 100, 2000, "a key step saves too");
        var schedule = findChild(t.panel, "qsNightLightSchedule");
        laidOut(schedule);
        clickItem(schedule);
        compare(t.backend.calls[t.backend.calls.length - 1], "schedule true");
        verify(findChild(t.panel, "qsNightLightScheduleSwitch").checked);
        clickItem(findChild(t.panel, "qsNightLightSettings"));
        compare(asked.count, 1);
        compare(asked.signalArguments[0][0], "display", "the rest is in Settings > Display");
    }
    function test_power_modes_page() {
        var t = make({ powerSaver: false });
        verify(Controls.catalog.powerSaver.dualTarget, "the tile has a details side");
        t.panel.details = "powerSaver";
        var page = findChild(t.panel, "qsPowerPage");
        tryVerify(() => page && page.visible);
        verify(!findChild(t.panel, "qsNightLightPage").visible);
        laidOut(findChild(t.panel, "qsPowerMode_performance"));
        verify(findChild(t.panel, "qsPowerMode_balanced").selected, "the current mode is marked");
        verify(!findChild(t.panel, "qsPowerMode_performance").selected);
        clickItem(findChild(t.panel, "qsPowerMode_performance"));
        compare(t.backend.calls[t.backend.calls.length - 1], "profile performance");
        verify(findChild(t.panel, "qsPowerMode_performance").selected);
        t.backend.performanceAvailable = false;
        tryVerify(() => findChild(t.panel, "qsPowerMode_performance") === null, 1000, "no Performance where the machine has none");
        verify(findChild(t.panel, "qsPowerMode_power-saver"));
        compare(Details.powerProfiles(true).map(p => p.id).join(), "performance,balanced,power-saver");
        compare(Details.powerProfiles(false).map(p => p.id).join(), "balanced,power-saver");
    }

    function test_edit_mode_moves_tiles_with_the_keyboard() {
        // the grid's keys (D107) reach it inside the panel: a click selects, Left swaps with the tile before
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "tilesEdited" });
        clickItem(findChild(t.panel, "qsEditTiles"));
        const before = t.panel.tiles.map(x => x.id);
        const i = before.indexOf("bluetooth");
        clickItem(tile(t.panel, "bluetooth"));
        verify(findChild(t.panel, "qsGrid").activeFocus, "the grid has the keys");
        keyClick(Qt.Key_Left);
        compare(spy.count, 1, "the move is saved");
        const order = findChild(t.panel, "qsGrid").items.slice().sort((a, b) => a.row - b.row || a.col - b.col).map(x => x.id);
        compare(order.indexOf("bluetooth"), i - 1, "a place earlier: " + order.join());
    }

    function test_edit_mode_adds_tiles() {
        var t = make();
        var spy = createTemporaryObject(spyComp, root, { target: t.panel, signalName: "tilesEdited" });
        verify(!findChild(t.panel, "qsAdd_powerSaver").visible, "only in edit mode");
        t.panel.editMode = true;
        waitForRendering(t.panel);
        compare(t.panel.addableTiles.join(), "powerSaver", "what the defaults leave out");
        verify(!findChild(t.panel, "qsAdd_wifi"), "a shown tile is not offered");
        clickItem(findChild(t.panel, "qsAdd_powerSaver"));
        compare(spy.count, 1);
        compare(JSON.stringify(spy.signalArguments[0][0].slice(-1)), JSON.stringify([{ id: "powerSaver", w: 2 }]),
                "wide: it has a details side (D108)");
        compare(t.panel.addableTiles.length, 0);
        // removing one offers it again, wide if it has a details side
        t.panel.tiles = [{ id: "mic", w: 1 }];
        compare(t.panel.addableTiles.join(), "wifi,bluetooth,dark,airplane,dnd,nightLight,powerSaver", "in catalog order");
        t.panel.addTile("bluetooth");
        compare(JSON.stringify(t.panel.tiles), JSON.stringify([{ id: "mic", w: 1 }, { id: "bluetooth", w: 2 }]));
        t.panel.addTile("bluetooth");
        t.panel.addTile("nope");
        compare(t.panel.tiles.length, 2, "no twice, nothing unknown");
        compare(spy.count, 2);
    }

    function test_dnd_and_power_saver_tiles() {
        var t = make({ dnd: true, powerSaverAvailable: false });
        t.panel.tiles = [{ id: "dnd", w: 2 }, { id: "powerSaver", w: 2 }];
        tryCompare(t.panel, "appearProgress", 1, 2000);
        waitForRendering(t.panel);
        var d = tile(t.panel, "dnd");
        verify(d.active);
        compare(d.secondaryText, "On");
        compare(d.iconName, "do_not_disturb_on");
        clickItem(d);
        verify(t.backend.calls.indexOf("dnd false") >= 0, "a click asks to turn it off: " + t.backend.calls);
        var p = tile(t.panel, "powerSaver");
        verify(!p.available, "no power-profiles-daemon");
        compare(p.secondaryText, "Unavailable");
        t.backend.powerSaverAvailable = true;
        compare(p.secondaryText, "Off");
        mouseClick(p, ControlSpec.tileSpec.iconSize, p.height / 2);     // its icon toggles; the body opens its page
        verify(t.backend.calls.indexOf("powerSaver true") >= 0, "" + t.backend.calls);
        t.backend.powerSaver = true;
        verify(p.active);
    }

    function test_night_light_tile() {
        var t = make({ nightLightAvailable: false });
        tryCompare(t.panel, "appearProgress", 1, 2000);
        var n = tile(t.panel, "nightLight");
        verify(n.visible, "among the defaults");
        compare(n.secondaryText, "Unavailable", "no wlsunset");
        t.backend.nightLightAvailable = true;
        compare(n.secondaryText, "Off");
        mouseClick(n, ControlSpec.tileSpec.iconSize, n.height / 2);     // its icon toggles (D108)
        compare(t.backend.calls[t.backend.calls.length - 1], "nightLight true");
        t.backend.nightLight = true;
        verify(n.active);
        compare(n.iconName, "nightlight");
        compare(n.secondaryText, "On");
        t.backend.nightLightScheduled = true;
        compare(n.secondaryText, "Sunset to sunrise");
    }

    function test_night_light_command() {
        const o = { temperature: 3500, schedule: false, latitude: null, longitude: null, sunset: "19:00", sunrise: "07:00" };
        compare(NightLight.command(o).join(" "), "wlsunset -t 3500 -T 3501", "all day");
        o.schedule = true;
        compare(NightLight.command(o).join(" "), "wlsunset -t 3500 -T 6500 -S 07:00 -s 19:00", "no place: the times set");
        o.latitude = 52.52;
        compare(NightLight.command(o).join(" "), "wlsunset -t 3500 -T 6500 -S 07:00 -s 19:00", "half a place is none");
        o.longitude = -13.4;
        compare(NightLight.command(o).join(" "), "wlsunset -t 3500 -T 6500 -l 52.52 -L -13.4", "the sun at the place");
        o.latitude = 0;
        compare(NightLight.command(o).join(" "), "wlsunset -t 3500 -T 6500 -l 0 -L -13.4", "0 is a place");
    }

    function test_saved_tiles_are_made_safe() {
        compare(JSON.stringify(Controls.tiles(null)), JSON.stringify(Controls.defaultTiles), "nothing saved: the defaults");
        compare(JSON.stringify(Controls.tiles({ id: "wifi" })), JSON.stringify(Controls.defaultTiles), "not a list");
        compare(JSON.stringify(Controls.tiles([])), "[]", "an empty layout stays empty");
        compare(JSON.stringify(Controls.tiles([{ id: "dnd", w: 2 }, { id: "gone", w: 1 }, null, { id: "dnd", w: 1 },
                                               { id: "mic", w: 4 }])),
                JSON.stringify([{ id: "dnd", w: 2 }, { id: "mic", w: 1 }]), "unknown, twice and odd widths");
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
