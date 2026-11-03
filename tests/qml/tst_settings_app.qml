import QtQuick
import QtTest
import qs.common
import qs.settingsapp
import "../qs/settingsapp/Model.js" as Model
import "../qs/settingsapp/Pages.js" as Pages
import "../qs/services/SettingsSchema.js" as Schema

TestCase {
    id: root
    name: "SettingsApp"
    width: 1100
    height: 760
    visible: true
    when: windowShown

    function cleanup() { Motion.speed = 1; }

    // The Settings service as far as the app uses it.
    Component {
        id: storeComp
        QtObject {
            property var values: ({ "motion.speed": 1, "notifications.sound": true, "wallpaper.path": "/pics/a.png",
                                    "wallpaper.palette": true, "lock.idleMinutes": 10, "lock.beforeSleep": true,
                                    "polkit.agent": true, "shelf.pins": ["firefox", "foot"],
                                    "appColors.enabled": false, "appColors.gtk": false, "appColors.qt": false,
                                    "appColors.kitty": false, "appColors.ghostty": false, "appColors.btop": false,
                                    "appColors.nvim": false, "appColors.firefox": false,
                                    "style.mode": "dark", "style.scheme": "scheme-tonal-spot", "style.contrast": 0,
                                    "style.seed": "#134aae" })
            property var managed: ({})
            property var sets: []
            readonly property string configDir: "/home/u/.config/rutile"
            function value(key) { return values[key]; }
            function isManaged(key) { return !!managed[key]; }
            function set(key, value) {
                if (managed[key]) return false;
                sets = sets.concat([[key, value]]);
                const v = Object.assign({}, values);
                v[key] = value;
                values = v;
                return true;
            }
        }
    }
    Component { id: appComp; SettingsApp { anchors.fill: parent } }
    // the Sound page's backend (SoundPage.qml's interface), recording what it is asked
    Component {
        id: soundComp
        QtObject {
            property bool available: true
            property var outputs: [{ id: 41, name: "Speakers" }, { id: 42, name: "Headphones" }]
            property var inputs: [{ id: 51, name: "Built-in microphone" }]
            property int output: 41
            property int input: 51
            property real volume: 0.4
            property bool muted: false
            property real inputVolume: 0.7
            property bool inputMuted: false
            property var calls: []
            function call(name, arg) { calls = calls.concat([name + ":" + arg]); }
            function setOutput(id) { call("setOutput", id); output = id; }
            function setInput(id) { call("setInput", id); input = id; }
            function setVolume(v) { call("setVolume", v.toFixed(2)); volume = v; }
            function setMuted(m) { call("setMuted", m); muted = m; }
            function setInputVolume(v) { call("setInputVolume", v.toFixed(2)); inputVolume = v; }
            function setInputMuted(m) { call("setInputMuted", m); inputMuted = m; }
        }
    }
    Component { id: spyComp; SignalSpy {} }

    function make(storeProps) {
        const s = createTemporaryObject(storeComp, root, storeProps ?? {});
        const a = createTemporaryObject(appComp, root, { store: s });
        a.forceActiveFocus();               // as the window gives it
        waitForRendering(a);                // Columns lay out at polish, before the first frame
        return { s: s, a: a };
    }
    function open(t, id) {
        verify(t.a.openPage(id));
        waitForRendering(t.a);
    }
    function type(text) {
        for (const c of text) keyClick(c);
    }

    // ---- the model ----
    function test_kinds() {
        const rows = {};
        for (const p of Pages.pages)
            for (const s of Model.sections(p, Schema.schema, Pages.hints))
                for (const r of s.rows) rows[r.key] = r;
        compare(rows["notifications.sound"].kind, "switch");
        compare(rows["motion.speed"].kind, "slider");
        compare(rows["motion.speed"].step, 0.25);
        compare(rows["motion.speed"].maximum, 4);
        compare(rows["lock.idleMinutes"].kind, "choice");
        compare(rows["wallpaper.path"].kind, "path");
        compare(Model.kind({ type: "array" }, {}), "list", "a list (shelf.pins has a page of its own now)");
        verify(rows["polkit.agent"].advanced);
        compare(Model.kind({ type: "string", enum: ["a", "b"] }, {}), "choice");
        compare(Model.kind({ type: "integer", minimum: 0, maximum: 9 }, {}), "slider");
        compare(Model.kind({ type: "integer" }, {}), "text", "no limits, no slider");
        compare(Model.kind({ type: "number", minimum: 0 }, {}), "text", "both limits, or no slider");
        compare(Model.kind({ type: "array" }, {}), "list");
    }

    function test_every_setting_is_on_a_page() {
        const shown = [];
        for (const p of Pages.pages)
            for (const s of p.sections) shown.push(...s.keys.filter(k => Pages.hints[k]?.kind !== "action" && Pages.hints[k]?.kind !== "notice"));
        // and those a page of its own shows (its entries name them)
        for (const p of Pages.pages)
            for (const e of p.entries ?? []) if (Schema.schema.properties[e.key.split(".")[0]]?.properties?.[e.key.split(".")[1]]) shown.push(e.key);
        const all = [];
        const walk = (node, prefix) => {
            for (const [k, v] of Object.entries(node.properties ?? {})) {
                if (v.type === "object") walk(v, prefix + k + ".");
                else all.push(prefix + k);
            }
        };
        walk(Schema.schema, "");
        compare(shown.slice().sort().join(), all.slice().sort().join(), "each schema setting once, nothing else but actions, notices and pages' own");
        compare(new Set(Pages.pages.map(p => p.id)).size, Pages.pages.length, "page ids are unique");
    }

    function test_advanced_goes_last() {
        const s = Model.sections(Pages.page("security"), Schema.schema, Pages.hints);
        compare(s.map(x => x.title).join(), "Screen lock,Advanced", "Passwords had only an advanced setting");
        compare(s[1].rows[0].key, "polkit.agent");
        verify(s[1].advanced);
        compare(Model.sections(null, Schema.schema, Pages.hints).length, 0);
        const odd = { sections: [{ title: "", keys: ["nope.missing", "lock.idleMinutes"] }] };
        compare(Model.sections(odd, Schema.schema, {})[0].rows.map(r => r.key).join(), "lock.idleMinutes",
                "a key the schema does not have is skipped");
        compare(Model.sections(odd, Schema.schema, {})[0].rows[0].step, 1, "an integer steps by 1");
        compare(Model.sections(odd, Schema.schema, {})[0].rows[0].kind, "slider", "limits and no hint: a slider");
    }

    function test_value_text() {
        compare(Model.valueText("lock.idleMinutes", 0, Pages.hints), "Never");
        compare(Model.valueText("lock.idleMinutes", 1, Pages.hints), "After 1 minute");
        compare(Model.valueText("lock.idleMinutes", 15, Pages.hints), "After 15 minutes");
        compare(Model.valueText("motion.speed", 0, Pages.hints), "Off");
        compare(Model.valueText("motion.speed", 1.5, Pages.hints), "1.5×");
        compare(Model.valueText("wallpaper.path", undefined, Pages.hints), "None");
        compare(Model.valueText("shelf.pins", ["a", "b"], Pages.hints), "a, b");
        compare(Model.valueText("shelf.pins", [], Pages.hints), "None");
        compare(Model.valueText("shelf.pins", undefined, Pages.hints), "Not set");
        compare(Model.valueText("lock.beforeSleep", false, Pages.hints), "Off");
    }

    function test_search_ranks() {
        const keys = q => Model.search(q, Pages.pages, Schema.schema, Pages.hints).map(h => h.page + "/" + h.key);
        compare(keys("")[0], undefined);
        compare(keys("   ").length, 0);
        compare(keys("wallp")[0], "wallpaper/", "the page by its title first");
        verify(keys("wallp").indexOf("wallpaper/wallpaper.path") > 0, "then its settings");
        compare(keys("animation speed")[0], "accessibility/motion.speed", "every word, by title");
        compare(keys("dock")[0], "shelf/", "aliases");
        compare(keys("pkexec")[0], "security/polkit.agent", "a setting's aliases");
        compare(keys("SOUND")[0], "sound/", "any case");
        verify(keys("SOUND").indexOf("notifications/notifications.sound") > 0);
        verify(keys("suspends").indexOf("security/lock.beforeSleep") >= 0, "descriptions");
        compare(keys("zzzz").length, 0);
        compare(Model.score("Lock when idle", "when id"), 2);
        compare(Model.score("Lock when idle", "hen"), 1);
        compare(Model.score("Lock when idle", "hen zz"), 0, "every word must be there");
        compare(Model.score("Lock when idle", "lock w"), 3);
        compare(Model.score("", "a"), 0);
    }

    // ---- the app ----
    function test_home_and_pages() {
        const t = make();
        compare(t.a.currentPage, "wallpaper");
        compare(findChild(t.a, "settingsTitle").text, "Wallpaper & style");
        for (const p of Pages.pages) verify(findChild(t.a, "settingsPage_" + p.id), p.id);
        verify(findChild(t.a, "settingsPage_wallpaper").selected);
        // the list is longer than the window now: scroll it down to Security first
        const sec = findChild(t.a, "settingsPage_security");
        let flick = sec.parent;
        while (flick && flick.contentY === undefined) flick = flick.parent;
        flick.contentY = flick.contentHeight - flick.height;
        waitForRendering(t.a);
        mouseClick(sec);
        waitForRendering(t.a);
        compare(t.a.currentPage, "security");
        compare(findChild(t.a, "settingsTitle").text, "Security & privacy");
        verify(findChild(t.a, "settingsPage_security").selected && !findChild(t.a, "settingsPage_wallpaper").selected);
        verify(findChild(t.a, "setting_lock.idleMinutes"));
        verify(findChild(t.a, "setting_polkit.agent"));
        verify(!findChild(t.a, "setting_wallpaper.path"), "only this page's settings");
        verify(!t.a.openPage("nope"));
        compare(t.a.currentPage, "security");
    }

    function test_switch() {
        const t = make();
        open(t, "notifications");
        const row = findChild(t.a, "setting_notifications.sound");
        const sw = findChild(row, "settingSwitch_notifications.sound");
        verify(sw.checked);
        compare(row.item.supportingText, Schema.schema.properties.notifications.properties.sound.description);
        mouseClick(sw);
        compare(t.s.sets, [["notifications.sound", false]]);
        verify(!sw.checked, "follows the store");
        mouseClick(row, 40, row.height / 2);
        compare(t.s.sets[1], ["notifications.sound", true], "a click on the row toggles too");
        t.s.values = Object.assign({}, t.s.values, { "notifications.sound": false });
        verify(!sw.checked, "and a change from elsewhere");
    }

    function test_choice_menu() {
        const t = make();
        open(t, "security");
        const row = findChild(t.a, "setting_lock.idleMinutes");
        compare(row.item.supportingText, Schema.schema.properties.lock.properties.idleMinutes.description);
        compare(row.shownValue, "After 10 minutes");
        mouseClick(row);
        verify(row.menuOpen);
        compare(t.a.menuKey, "lock.idleMinutes");
        const menu = findChild(t.a, "settingMenu");
        tryVerify(() => menu.item && menu.motion.progress > 0.99, 2000);
        verify(menu.y >= row.mapToItem(t.a, 0, row.height).y - 1, "under the row");
        compare(findChild(menu.item, "settingChoice_4").iconName, "check", "the current one is checked");
        // above everything: the later Advanced section does not cover it (it did when the menu was the row's)
        waitForRendering(t.a);
        const two = findChild(menu.item, "settingChoice_2");
        const c = two.mapToItem(t.a, two.width / 2, two.height / 2);
        compare(t.a.childAt(c.x, c.y), menu, "the menu is on top where the rows below are");
        mouseClick(two);
        compare(t.s.sets, [["lock.idleMinutes", 2]]);
        verify(!row.menuOpen, "it closes");
        compare(row.shownValue, "After 2 minutes");
        tryVerify(() => !menu.active, 2000, "and unloads");

        row.item.forceActiveFocus();
        keyClick(Qt.Key_Return);
        verify(row.menuOpen, "Enter on the row opens it");
        keyClick(Qt.Key_Return);
        verify(!row.menuOpen, "and again closes it");
        mouseClick(row);
        verify(row.menuOpen);
        keyClick(Qt.Key_Escape);
        verify(!row.menuOpen, "Escape closes it");
        mouseClick(row);
        verify(row.menuOpen);
        mouseClick(t.a, t.a.width - 300, t.a.height - 40);
        verify(!row.menuOpen, "a click on the page's empty space closes it");
        mouseClick(row);
        mouseClick(findChild(t.a, "settingsPage_network"));
        verify(!row.menuOpen, "a click on the sidebar only closes it");
        compare(t.a.currentPage, "security");
        compare(t.s.sets.length, 1, "and chooses nothing");
    }

    function test_menu_opens_above_near_the_bottom() {
        const t = make();
        t.a.anchors.fill = undefined;
        t.a.width = 1100;
        t.a.height = 330;
        waitForRendering(t.a);
        open(t, "security");
        const row = findChild(t.a, "setting_lock.idleMinutes");
        mouseClick(row);
        const menu = findChild(t.a, "settingMenu");
        verify(!menu.below, "no room below");
        tryVerify(() => menu.item && menu.motion.progress > 0.99, 2000);
        verify(menu.y >= 0);
    }

    function test_slider_saves_when_still() {
        const t = make();
        open(t, "accessibility");
        const row = findChild(t.a, "setting_motion.speed");
        const sl = findChild(row, "settingSlider_motion.speed");
        compare(row.item.trailingText, "1×");
        sl.moved(2);
        wait(100);
        sl.moved(2.5);
        wait(100);
        compare(t.s.sets.length, 0, "not while it moves");
        compare(sl.value, 2.5);
        tryVerify(() => t.s.sets.length === 1, 1000);
        compare(t.s.sets[0], ["motion.speed", 2.5]);
        compare(row.item.trailingText, "2.5×");
        t.s.values = Object.assign({}, t.s.values, { "motion.speed": 0.5 });
        compare(sl.value, 0.5, "follows a change from elsewhere");
    }

    function test_managed() {
        const t = make({ managed: { "notifications.sound": true, "lock.idleMinutes": true } });
        open(t, "notifications");
        const row = findChild(t.a, "setting_notifications.sound");
        compare(row.item.supportingText, "Set in your Nix configuration");
        verify(!row.item.enabled);
        mouseClick(row);
        compare(t.s.sets.length, 0);
        open(t, "security");
        const idle = findChild(t.a, "setting_lock.idleMinutes");
        compare(idle.item.supportingText, "Set in your Nix configuration: After 10 minutes");
        mouseClick(idle);
        verify(!idle.menuOpen, "no menu");
    }

    function test_path_asks_for_a_file() {
        const t = make();
        const asked = createTemporaryObject(spyComp, root, { target: t.a, signalName: "pathRequested" });
        const row = findChild(t.a, "setting_wallpaper.path");
        compare(row.item.supportingText, "/pics/a.png");
        mouseClick(findChild(row, "settingChoose_wallpaper.path"));
        compare(asked.count, 1);
        compare(asked.signalArguments[0][0], "wallpaper.path");
        compare(asked.signalArguments[0][1], ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"], "the hint's filters");
        mouseClick(row, 40, row.height / 2);
        compare(asked.count, 2, "a click on the row asks too");
        compare(t.s.sets.length, 0, "the window sets what was chosen");

        const m = make({ managed: { "wallpaper.path": true } });
        const mAsked = createTemporaryObject(spyComp, root, { target: m.a, signalName: "pathRequested" });
        const mRow = findChild(m.a, "setting_wallpaper.path");
        verify(!findChild(mRow, "settingChoose_wallpaper.path"), "set in Nix: no Choose button");
        mouseClick(mRow, 40, mRow.height / 2);
        compare(mAsked.count, 0);
    }

    // the style (D65): mode and color style as menus, contrast a slider, the color as swatches
    function test_style_rows() {
        const rows = {};
        for (const s of Model.sections(Pages.page("wallpaper"), Schema.schema, Pages.hints))
            for (const r of s.rows) rows[r.key] = r;
        compare(rows["style.mode"].kind, "choice");
        compare(Model.valueText("style.mode", "light", Pages.hints), "Light");
        compare(Model.valueText("style.scheme", "scheme-fruit-salad", Pages.hints), "Fruit salad");
        compare(rows["style.scheme"].choices.length, 9);
        compare(rows["style.contrast"].kind, "slider");
        compare(Model.valueText("style.contrast", 0, Pages.hints), "Standard");
        compare(Model.valueText("style.contrast", 0.5, Pages.hints), "+0.5");
        compare(rows["style.seed"].kind, "color");
        compare(rows["style.seed"].swatches.length, 8);
        const t = make();
        open(t, "wallpaper");
        const seed = findChild(t.a, "setting_style.seed");
        verify(seed, "the color's row");
        const chosen = findChild(seed, "settingSwatch_#134aae");
        const green = findChild(seed, "settingSwatch_#386a20");
        verify(chosen.chosen && !green.chosen, "the current color ringed");
        mouseClick(green);
        compare(t.s.sets[t.s.sets.length - 1], ["style.seed", "#386a20"]);
        verify(green.chosen && !chosen.chosen, "and the ring moves");
        t.s.managed = { "style.seed": true };
        verify(!findChild(seed, "settingSwatch_#386a20"), "set in Nix: no swatches");
    }

    function test_app_colors_wait_for_the_main_switch() {
        const t = make();
        const main = findChild(t.a, "setting_appColors.enabled");
        const kitty = findChild(t.a, "setting_appColors.niri");      // the first app's row: in view
        verify(main.item.enabled, "the main switch works");
        verify(!kitty.applies && !kitty.item.enabled, "an app's switch is greyed out while it is off");
        mouseClick(kitty, 40, kitty.height / 2);
        compare(t.s.sets.length, 0, "and takes no click");
        mouseClick(findChild(main, "settingSwitch_appColors.enabled"));
        compare(t.s.sets, [["appColors.enabled", true]]);
        verify(kitty.applies && kitty.item.enabled, "then it works");
        mouseClick(findChild(kitty, "settingSwitch_appColors.niri"));
        compare(t.s.sets[1], ["appColors.niri", true]);
        // every app's switch waits for the main one (niri's, KDE's and the folders' had been left out)
        const apps = Object.keys(Schema.schema.properties.appColors.properties).filter(k => k !== "enabled");
        verify(apps.length >= 10);
        for (const a of apps)
            compare(Pages.hints["appColors." + a]?.requires, "appColors.enabled", "appColors." + a + " requires the main switch");
        const keys = q => Model.search(q, Pages.pages, Schema.schema, Pages.hints).map(h => h.key);
        verify(keys("pywalfox").indexOf("appColors.firefox") === 0, "found by what people call it");
        verify(keys("matugen").indexOf("appColors.enabled") >= 0);
    }

    // a notice (D74): shown only while its condition holds (niri does not include rutile.kdl)
    function test_notice() {
        const t = make();
        open(t, "input");
        const n = findChild(t.a, "setting_notice.niriInclude");
        verify(n && !n.visible, "no condition: hidden");
        t.a.conditions = { niriNotIncluded: true };
        waitForRendering(t.a);
        verify(n.visible);
        compare(n.item.iconName, "info");
        verify(n.item.supportingText.indexOf('include optional=true "rutile.kdl"') >= 0, n.item.supportingText);
        mouseClick(n);
        compare(t.s.sets.length, 0, "nothing to set");
        compare(Model.search("niri does not read", Pages.pages, Schema.schema, Pages.hints).length, 0, "not a search result");
    }

    // an action (D66): a button, no setting; found by search; the app asks the window to run it
    function test_flatpak_action() {
        const rows = {};
        for (const s of Model.sections(Pages.page("wallpaper"), Schema.schema, Pages.hints))
            for (const r of s.rows) rows[r.key] = r;
        compare(rows["action.flatpak"].kind, "action");
        compare(rows["action.flatpak"].title, "Flatpak apps");
        compare(rows["action.flatpak"].button, "Set up…");
        const keys = q => Model.search(q, Pages.pages, Schema.schema, Pages.hints).map(h => h.key);
        compare(keys("flatpak")[0], "action.flatpak");

        const t = make();
        const asked = createTemporaryObject(spyComp, root, { target: t.a, signalName: "actionRequested" });
        mouseClick(t.a.search);
        type("flatpak");
        waitForRendering(t.a);
        mouseClick(findChild(t.a, "settingsResult_0"));
        waitForRendering(t.a);
        compare(t.a.currentPage, "wallpaper");
        const row = findChild(t.a, "setting_action.flatpak");
        verify(row.item.enabled);
        compare(row.item.supportingText, Pages.hints["action.flatpak"].description);
        const button = findChild(row, "settingAction_action.flatpak");
        verify(button && button.visible);
        mouseClick(button);
        compare(asked.count, 1);
        compare(asked.signalArguments[0][0], "action.flatpak");
        mouseClick(row, 40, row.height / 2);
        compare(asked.count, 2, "a click on the row asks too");
        compare(t.s.sets.length, 0, "no setting changes");
    }

    function test_search() {
        const t = make();
        mouseClick(t.a.search);
        type("idle");
        waitForRendering(t.a);
        verify(t.a.searching);
        verify(!findChild(t.a, "settingsNoResults").visible, "results, so no 'no results'");
        verify(findChild(t.a, "settingsResults").visible);
        verify(!findChild(t.a, "settingsPages").visible);
        const first = findChild(t.a, "settingsResult_0");
        compare(first.text, "Lock when idle");
        compare(first.supportingText, "Security & privacy");
        mouseClick(first);
        waitForRendering(t.a);
        compare(t.a.currentPage, "security");
        compare(t.a.query, "", "the search clears");
        compare(t.a.highlightKey, "lock.idleMinutes");
        verify(findChild(t.a, "setting_lock.idleMinutes").highlighted, "the setting is marked");
        const ring = findChild(t.a, "settingRing");
        const row = findChild(t.a, "setting_lock.idleMinutes");
        tryVerify(() => ring.visible && ring.opacity === 1, 1000, "a ring around it");
        const at = row.mapToItem(ring.parent, 0, 0);
        compare(Qt.rect(ring.x, ring.y, ring.width, ring.height), Qt.rect(at.x, at.y, row.width, row.height), "exactly");
        // the window resized after it opened (niri tiles a new window): the ring follows the row
        t.a.anchors.fill = undefined;
        t.a.width = 900;
        tryVerify(() => ring.width === row.width && ring.x === row.mapToItem(ring.parent, 0, 0).x
                  && ring.y === row.mapToItem(ring.parent, 0, 0).y, 1000, "still around it after a resize");
        verify(row.width < 1100 - 400, "the row did shrink: " + row.width);
        tryCompare(t.a, "highlightKey", "", 3000, "for a moment");
        verify(ring.opacity > 0, "then it fades, not gone at once");
        tryCompare(ring, "visible", false, 3000, "faded");

        mouseClick(t.a.search);
        type("qqqq");
        waitForRendering(t.a);
        verify(findChild(t.a, "settingsNoResults").visible);
        keyClick(Qt.Key_Escape);
        verify(!t.a.searching, "Escape clears it");
        type("dock");
        keyClick(Qt.Key_Return);
        compare(t.a.currentPage, "shelf", "Enter opens the best one");
        t.a.forceActiveFocus();
        keyClick(Qt.Key_F);
        verify(!t.a.search.activeFocus, "F alone is not Ctrl+F");
        keyClick(Qt.Key_F, Qt.ControlModifier);
        verify(t.a.search.activeFocus, "Ctrl+F");
    }

    function test_about() {
        const t = make();
        open(t, "about");
        compare(findChild(t.a, "aboutSettingsFile").supportingText, "/home/u/.config/rutile/settings.json");
        open(t, "wallpaper");
        tryVerify(() => !findChild(t.a, "aboutSettingsFile"), 1000, "only on its page");
    }

    // pages of their own (plan 5.2): a view loaded only while open, with the page's backend
    function test_sound_page() {
        const t = make();
        const b = createTemporaryObject(soundComp, root);
        verify(!findChild(t.a, "setting_sound.output"), "not loaded before it is open");
        t.a.backend = b;
        open(t, "sound");
        compare(t.a.pageView.status, Loader.Ready);
        const out = findChild(t.a, "setting_sound.output");
        verify(out && out.visible);
        verify(!findChild(t.a, "soundUnavailable").visible);
        compare(findChild(t.a, "soundVolume_output").trailingText, "40%");
        compare(findChild(t.a, "soundVolume_input").trailingText, "70%");
        compare(findChild(t.a, "soundSlider_output").value, 0.4);
        const speakers = findChild(t.a, "soundDevice_output_0");
        const phones = findChild(t.a, "soundDevice_output_1");
        compare(speakers.text, "Speakers");
        verify(speakers.selected && !phones.selected, "the default is marked");
        compare(findChild(t.a, "soundVolume_output").position, "first");
        compare(phones.position, "last");

        mouseClick(phones);
        compare(b.calls, ["setOutput:42"]);
        verify(phones.selected && !speakers.selected, "follows the backend");
        mouseClick(findChild(t.a, "soundMute_output"));
        compare(b.calls[1], "setMuted:true");
        compare(findChild(t.a, "soundVolume_output").trailingText, "Muted");
        compare(findChild(t.a, "soundVolume_output").iconName, "volume_off");
        const slider = findChild(t.a, "soundSlider_input");
        mouseClick(slider, slider.width - 2, slider.height / 2);
        verify(/^setInputVolume:(0\.9\d|1\.00)$/.test(b.calls[2]), b.calls[2]);
        mouseClick(findChild(t.a, "soundMute_input"));
        compare(b.calls[3], "setInputMuted:true");
        compare(findChild(t.a, "soundVolume_input").iconName, "mic_off");
        mouseClick(findChild(t.a, "soundDevice_input_0"));
        compare(b.calls[4], "setInput:51");

        b.inputs = [];
        b.input = -1;
        waitForRendering(t.a);
        verify(!findChild(t.a, "soundSlider_input").enabled, "no microphone: nothing to change");
        verify(!findChild(t.a, "soundDevice_input_0"));

        b.available = false;
        waitForRendering(t.a);
        verify(findChild(t.a, "soundUnavailable").visible, "PipeWire not running: says so");
        verify(!findChild(t.a, "setting_sound.output"));

        open(t, "wallpaper");
        tryVerify(() => !findChild(t.a, "soundUnavailable"), 1000, "unloaded when another page opens");
        compare(t.a.pageView.status, Loader.Null);
    }

    function test_sound_without_a_backend() {
        const t = make();
        open(t, "sound");
        verify(findChild(t.a, "soundUnavailable").visible, "no backend yet: no devices, no error");
    }

    function test_page_entries_are_searched_and_marked() {
        const keys = q => Model.search(q, Pages.pages, Schema.schema, Pages.hints).map(h => h.page + "/" + h.key);
        compare(keys("microphone")[0], "sound/sound.input");
        compare(keys("headphones")[0], "sound/sound.output");
        verify(keys("sound").indexOf("sound/") >= 0, "the page itself");
        const t = make();
        t.a.backend = createTemporaryObject(soundComp, root);
        mouseClick(t.a.search);
        type("microphone");
        waitForRendering(t.a);
        mouseClick(findChild(t.a, "settingsResult_0"));
        waitForRendering(t.a);
        compare(t.a.currentPage, "sound");
        compare(t.a.highlightKey, "sound.input");
        verify(t.a.findRow("sound.input"), "the view's group is found to scroll to");
    }

    function test_narrow() {
        const t = make();
        t.a.anchors.fill = undefined;
        t.a.width = 500;
        t.a.height = 700;
        waitForRendering(t.a);
        verify(t.a.narrow);
        verify(findChild(t.a, "settingsPages").visible, "the list first");
        verify(!findChild(t.a, "settingsPage_wallpaper").selected, "nothing marked in a list alone");
        mouseClick(findChild(t.a, "settingsPage_network"));
        verify(t.a.pageShown);
        waitForRendering(t.a);
        verify(!findChild(t.a, "settingsPages").visible, "then the page alone");
        const back = findChild(t.a, "settingsBack");
        verify(back.visible);
        mouseClick(back);
        verify(!t.a.pageShown);
        mouseClick(findChild(t.a, "settingsPage_network"));
        verify(t.a.pageShown);
        t.a.search.text = "dock";
        verify(!t.a.pageShown, "a search shows the results, not the page");
        t.a.search.text = "";
        mouseClick(findChild(t.a, "settingsPage_network"));
        t.a.forceActiveFocus();
        keyClick(Qt.Key_F, Qt.ControlModifier);
        verify(!t.a.pageShown && t.a.search.activeFocus, "Ctrl+F brings the search back");
        verify(findChild(t.a, "settingsPages").visible);
        t.a.width = 1100;
        verify(!findChild(t.a, "settingsBack").visible, "wide: no back button");
    }

    function test_highlight_scrolls() {
        const t = make();
        t.a.anchors.fill = undefined;
        t.a.width = 1100;
        t.a.height = 260;
        t.a.openPage("security", "polkit.agent");
        const row = findChild(t.a, "setting_polkit.agent");
        const flick = findChild(t.a, "settingsPageFlick");
        tryVerify(() => {
            const y = row.mapToItem(t.a, 0, 0).y;
            return flick.contentY > 0 && y >= 0 && y + row.height <= t.a.height;
        }, 1000, "scrolled into view");
        open(t, "security");
        compare(flick.contentY, 0, "opening a page starts at its top");
        open(t, "wallpaper");
        tryCompare(findChild(t.a, "settingsTitle"), "text", "Wallpaper & style");
    }
}
