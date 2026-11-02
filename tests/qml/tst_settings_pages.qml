// The settings app's pages of their own (plan 5.2, D67) beyond Sound: Network and Bluetooth, each with a fake
// backend that has the page's interface and records what it is asked.
import QtQuick
import QtTest
import qs.common
import qs.settingsapp
import "../qs/settingsapp/Model.js" as Model
import "../qs/settingsapp/Pages.js" as Pages
import "../qs/services/SettingsSchema.js" as Schema
import "../qs/settingsapp/pages/Display.js" as Display
import "../qs/settingsapp/pages/Apps.js" as Apps

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

    // niri's outputs as `niri msg -j outputs` gave them on the maintainer's machine (modes trimmed), and a
    // second, rotated and scaled, and a third that is off
    function niriOutputs() {
        return [
            { name: "DP-1", make: "Microstep", model: "MSI MP243X", current_mode: 1, vrr_supported: true, vrr_enabled: false,
              modes: [{ width: 1920, height: 1080, refresh_rate: 60000, is_preferred: true },
                      { width: 1920, height: 1080, refresh_rate: 99999, is_preferred: false },
                      { width: 1920, height: 1080, refresh_rate: 74973, is_preferred: false },
                      { width: 1920, height: 1080, refresh_rate: 60000, is_preferred: false },
                      { width: 1280, height: 1024, refresh_rate: 75025, is_preferred: false },
                      { width: 1680, height: 1050, refresh_rate: 59954, is_preferred: false }],
              logical: { x: 0, y: 0, width: 1920, height: 1080, scale: 1.0, transform: "Normal" } },
            { name: "HDMI-A-1", make: "Dell", model: "", current_mode: 0, vrr_supported: false, vrr_enabled: false,
              modes: [{ width: 3840, height: 2160, refresh_rate: 60000, is_preferred: true }],
              logical: { x: 1920, y: 0, width: 1080, height: 1920, scale: 1.3, transform: "Flipped90" } },
            { name: "eDP-1", make: "", model: "", current_mode: null, vrr_supported: false, vrr_enabled: false,
              modes: [{ width: 2560, height: 1600, refresh_rate: 165000, is_preferred: true }], logical: null }
        ];
    }
    Component {
        id: displayComp
        QtObject {
            property bool available: true
            property var outputs: []
            property string error: ""
            property var calls: []
            property string copied: ""
            function command(name, args) { calls = calls.concat([name + " " + args.join(" ")]); }
            function copy(text) { copied = text; }
        }
    }

    function test_display_model() {
        const [dp, hdmi, edp] = niriOutputs();
        compare(Display.title(dp), "MSI MP243X");
        compare(Display.title(hdmi), "Dell", "no model: the make");
        compare(Display.title(edp), "eDP-1", "neither: the connector");
        verify(Display.enabled(dp) && !Display.enabled(edp));
        compare(Display.current(dp).refresh_rate, 99999);
        compare(Display.resolutions(dp).map(r => r.label), ["1920 × 1080", "1680 × 1050", "1280 × 1024"], "largest first, once each");
        compare(Display.rateLabel(59940), "59.94 Hz", "not rounded into 60");
        compare(Display.rates(dp, 1920, 1080).map(m => Display.rateLabel(m.refresh_rate)), ["100 Hz", "74.97 Hz", "60 Hz"],
                "fastest first, a rate once");
        compare(Display.modeArg(Display.current(dp)), "1920x1080@99.999");
        compare(Display.modeFor(dp, 1920, 1080).refresh_rate, 60000, "a resolution chosen: its preferred mode");
        compare(Display.modeFor(dp, 1280, 1024).refresh_rate, 75025, "else the fastest");
        compare(Display.scales(dp).map(Display.scaleLabel), ["100%", "125%", "150%", "175%", "200%", "250%", "300%"]);
        verify(Display.scales(hdmi).indexOf(1.3) >= 0, "a scale set elsewhere stays a choice");
        compare(Display.transformLabel("90"), "90°");
        compare(Display.transformArg("270°"), "270");
        compare(Display.enabledCount(niriOutputs()), 2);
        compare(Display.kdl(dp), 'output "DP-1" {\n    mode "1920x1080@99.999"\n    scale 1\n}\n');
        compare(Display.kdl(hdmi), 'output "HDMI-A-1" {\n    mode "3840x2160@60.000"\n    scale 1.3\n    transform "flipped-90"\n}\n',
                "niri's config spelling");
        compare(Display.kdl(edp), 'output "eDP-1" {\n    off\n}\n');
        const vrr = Object.assign({}, dp, { vrr_enabled: true });
        verify(Display.kdl(vrr).indexOf("    variable-refresh-rate\n") > 0);
    }

    function test_display_page() {
        const t = make("display", displayComp);
        const a = t.a, b = t.b;
        b.outputs = niriOutputs();
        waitForRendering(a);
        verify(!findChild(a, "displayUnavailable").visible);
        compare(findChild(a, "displayOn_0").supportingText, "1920 × 1080, 100 Hz");
        verify(findChild(a, "displayVrr_0").visible, "VRR where supported");
        verify(!findChild(a, "displayVrr_1").visible);
        compare(findChild(a, "choice_display.DP-1.scale").current, "100%");
        compare(findChild(a, "choice_display.HDMI-A-1.scale").current, "130%");
        compare(findChild(a, "displayOn_2").supportingText, "Off");
        verify(!findChild(a, "choice_display.eDP-1.resolution").visible, "off: only its switch");

        // a choice through the app's menu
        mouseClick(findChild(a, "choice_display.DP-1.scale"));
        waitForRendering(a);
        compare(a.menuKey, "display.DP-1.scale");
        mouseClick(findChild(a, "settingChoice_2"));
        compare(b.calls, ["DP-1 scale 1.5"]);
        compare(a.menuKey, "", "closed");
        mouseClick(findChild(a, "choice_display.DP-1.resolution"));
        waitForRendering(a);
        mouseClick(findChild(a, "settingChoice_2"));
        compare(b.calls[1], "DP-1 mode 1280x1024@75.025");
        mouseClick(findChild(a, "choice_display.DP-1.rate"));
        waitForRendering(a);
        mouseClick(findChild(a, "settingChoice_2"));
        compare(b.calls[2], "DP-1 mode 1920x1080@60.000");
        mouseClick(findChild(a, "choice_display.DP-1.transform"));
        waitForRendering(a);
        mouseClick(findChild(a, "settingChoice_1"));
        compare(b.calls[3], "DP-1 transform 90");
        mouseClick(findChild(a, "displayVrrSwitch_0"));
        compare(b.calls[4], "DP-1 vrr on");
        mouseClick(findChild(a, "displayCopy_0"));
        compare(b.copied, Display.kdl(niriOutputs()[0]));

        // the last output on cannot be turned off
        verify(findChild(a, "displaySwitch_0").enabled, "two on: either can go off");
        const flick = findChild(a, "settingsPageFlick");
        flick.contentY = flick.contentHeight - flick.height;           // the third output, below
        waitForRendering(a);
        mouseClick(findChild(a, "displaySwitch_2"));
        compare(b.calls[b.calls.length - 1], "eDP-1 on");
        b.outputs = [niriOutputs()[0]];
        waitForRendering(a);
        verify(!findChild(a, "displaySwitch_0").enabled, "the only one on stays on");
        const n = b.calls.length;
        mouseClick(findChild(a, "displayOn_0"));
        compare(b.calls.length, n, "a click on its row does nothing either");

        b.error = "Error: output not found";
        waitForRendering(a);
        verify(findChild(a, "displayError").visible, "niri's complaint shows");
        b.available = false;
        waitForRendering(a);
        verify(findChild(a, "displayUnavailable").visible);
        verify(!findChild(a, "displayOn_0"));
    }

    Component {
        id: powerComp
        QtObject {
            property bool batteryAvailable: true
            property real battery: 0.43
            property string state: "discharging"
            property real timeToFull: 0
            property real timeToEmpty: 7500
            property real health: 0.91
            property bool profilesAvailable: true
            property bool hasPerformance: true
            property string profile: "balanced"
            property var holds: []
            property var calls: []
            function setProfile(name) { calls = calls.concat([name]); profile = name; }
        }
    }

    function test_power() {
        const t = make("power", powerComp);
        const a = t.a, b = t.b;
        const bat = findChild(a, "powerBattery");
        compare(bat.text, "43%");
        compare(bat.supportingText, "2 h 5 min left");
        compare(bat.iconName, "battery_3_bar");
        compare(findChild(a, "powerHealth").trailingText, "91%");
        verify(!findChild(a, "powerNothing").visible);
        verify(findChild(a, "powerMode_balanced").selected);

        mouseClick(findChild(a, "powerMode_power-saver"));
        compare(b.calls, ["power-saver"]);
        verify(findChild(a, "powerMode_power-saver").selected && !findChild(a, "powerMode_balanced").selected);

        b.state = "charging";
        b.timeToFull = 2400;
        compare(bat.supportingText, "Charging, full in 40 min");
        compare(bat.iconName, "battery_charging_full");
        b.timeToFull = 0;
        compare(bat.supportingText, "Charging", "no estimate: none shown");
        b.state = "full";
        compare(bat.supportingText, "Fully charged");
        b.state = "pending";
        compare(bat.supportingText, "Plugged in, not charging");
        b.health = -1;
        waitForRendering(a);
        verify(!findChild(a, "powerHealth").visible, "no health from UPower: no row");

        b.holds = [{ profile: "performance", app: "Steam", reason: "Game running" }];
        compare(findChild(a, "powerMode_performance").supportingText, "Held by Steam: Game running");
        b.hasPerformance = false;
        waitForRendering(a);
        verify(!findChild(a, "powerMode_performance"), "no performance mode on this machine: not offered");

        b.batteryAvailable = false;
        waitForRendering(a);
        verify(!findChild(a, "setting_power.battery").visible, "a desktop: no battery group");
        verify(findChild(a, "setting_power.mode").visible);
        b.profilesAvailable = false;
        waitForRendering(a);
        verify(findChild(a, "powerNothing").visible);
    }

    function test_apps_model() {
        const text = "@@entry a.desktop\nName=Alpha\nMimeType=text/plain;image/png;\n" +
                     "@@entry b.desktop\nName=Beta\nNoDisplay=true\nMimeType=text/plain;\n" +
                     "@@entry c.desktop\nName=Gamma\nType=Link\nMimeType=text/plain;\n" +
                     "@@entry a.desktop\nName=Alpha again\n" +
                     "@@list user /h/.config/mimeapps.list\n[Default Applications]\nimage/png=missing.desktop;a.desktop;\n" +
                     "@@list other /etc/xdg/mimeapps.list\n[Default Applications]\ntext/plain=b.desktop\n@@end\n";
        const p = Apps.parse(text);
        compare(Object.keys(p.entries).sort().join(), "a.desktop,b.desktop", "not a Link");
        compare(p.entries["a.desktop"].name, "Alpha", "the first file with an id wins");
        compare(Apps.defaultFor(p, "image/png"), "a.desktop", "the first installed one named");
        compare(Apps.defaultFor(p, "text/plain"), "b.desktop", "from a later list");
        compare(Apps.defaultFor(p, "video/mp4"), "");
        const text_ = Apps.KINDS.find(k => k.id === "text");
        compare(Apps.candidates(p, text_).map(e => e.id).join(), "a.desktop,b.desktop", "a NoDisplay app only as the default");
        const p2 = Apps.parse(text.replace("text/plain=b.desktop", "text/plain=a.desktop"));
        compare(Apps.candidates(p2, text_).map(e => e.id).join(), "a.desktop");
        compare(Apps.userList(p).path, "/h/.config/mimeapps.list");
        verify(!Apps.userList(p).link);

        compare(Apps.withDefault("", ["a/b", "c/d"], "x.desktop"), "[Default Applications]\na/b=x.desktop;\nc/d=x.desktop;\n");
        compare(Apps.withDefault("[Added Associations]\nt/p=y;\n", ["a/b"], "x.desktop"),
                "[Added Associations]\nt/p=y;\n\n[Default Applications]\na/b=x.desktop;\n");
        compare(Apps.withDefault("[Default Applications]\na/b=old.desktop;\ne/f=keep.desktop;\n\n[Removed Associations]\nq/r=z;\n",
                                 ["a/b"], "x.desktop"),
                "[Default Applications]\ne/f=keep.desktop;\na/b=x.desktop;\n\n[Removed Associations]\nq/r=z;\n",
                "replaced in place, the rest kept");
    }

    Component {
        id: appsComp
        QtObject {
            property bool available: true
            property bool managed: false
            property string error: ""
            property var kinds: [
                { id: "browser", title: "Web browser", icon: "language", current: "chromium.desktop",
                  apps: [{ id: "chromium.desktop", name: "Chromium" }, { id: "firefox.desktop", name: "Firefox" }] },
                { id: "pdf", title: "PDF documents", icon: "picture_as_pdf", current: "", apps: [] },
                { id: "text", title: "Text", icon: "description", current: "", apps: [{ id: "kate.desktop", name: "Kate" }] }
            ]
            property var calls: []
            function setDefault(kind, app) { calls = calls.concat([kind + ":" + app]); }
        }
    }

    function test_apps_page() {
        const t = make("apps", appsComp);
        const a = t.a, b = t.b;
        const browser = findChild(a, "choice_apps.browser");
        compare(browser.current, "Chromium");
        verify(browser.enabled);
        compare(findChild(a, "choice_apps.pdf").supportingText, "No app for this is installed");
        verify(!findChild(a, "choice_apps.pdf").enabled);
        compare(findChild(a, "choice_apps.text").current, "Not set", "apps, but no default: the system picks");
        mouseClick(browser);
        waitForRendering(a);
        mouseClick(findChild(a, "settingChoice_1"));
        compare(b.calls, ["browser:firefox.desktop"]);
        verify(!findChild(a, "appsManaged").visible);
        b.managed = true;
        waitForRendering(a);
        verify(findChild(a, "appsManaged").visible);
        verify(!browser.enabled, "home-manager's: nothing to change here");
        b.error = "Could not write mimeapps.list";
        waitForRendering(a);
        verify(findChild(a, "appsError").visible);
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
        compare(keys("resolution")[0], "display/display.outputs");
        compare(keys("monitor")[0], "display/");
        compare(keys("power saver")[0], "power/power.mode");
        compare(keys("battery")[0], "power/power.battery");
        compare(keys("default browser")[0], "apps/apps.defaults");
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
