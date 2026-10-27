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
                                    "polkit.agent": true, "shelf.pins": ["firefox", "foot"] })
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
        compare(rows["shelf.pins"].kind, "list");
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
            for (const s of p.sections) shown.push(...s.keys);
        const all = [];
        const walk = (node, prefix) => {
            for (const [k, v] of Object.entries(node.properties ?? {})) {
                if (v.type === "object") walk(v, prefix + k + ".");
                else all.push(prefix + k);
            }
        };
        walk(Schema.schema, "");
        compare(shown.slice().sort().join(), all.slice().sort().join(), "each schema setting once, nothing else");
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
        compare(keys("SOUND")[0], "notifications/notifications.sound", "any case");
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
        mouseClick(findChild(t.a, "settingsPage_security"));
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
        mouseClick(findChild(t.a, "settingsPage_shelf"));
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

    function test_read_only_kinds() {
        const t = make();
        compare(findChild(t.a, "setting_wallpaper.path").item.supportingText, "/pics/a.png");
        open(t, "shelf");
        const pins = findChild(t.a, "setting_shelf.pins");
        compare(pins.item.supportingText, "firefox, foot");
        mouseClick(pins);
        compare(t.s.sets.length, 0, "nothing to change here yet");
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
        tryCompare(t.a, "highlightKey", "", 3000, "for a moment");

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

    function test_narrow() {
        const t = make();
        t.a.anchors.fill = undefined;
        t.a.width = 500;
        t.a.height = 700;
        waitForRendering(t.a);
        verify(t.a.narrow);
        verify(findChild(t.a, "settingsPages").visible, "the list first");
        verify(!findChild(t.a, "settingsPage_wallpaper").selected, "nothing marked in a list alone");
        mouseClick(findChild(t.a, "settingsPage_shelf"));
        verify(t.a.pageShown);
        waitForRendering(t.a);
        verify(!findChild(t.a, "settingsPages").visible, "then the page alone");
        const back = findChild(t.a, "settingsBack");
        verify(back.visible);
        mouseClick(back);
        verify(!t.a.pageShown);
        mouseClick(findChild(t.a, "settingsPage_shelf"));
        verify(t.a.pageShown);
        t.a.search.text = "dock";
        verify(!t.a.pageShown, "a search shows the results, not the page");
        t.a.search.text = "";
        mouseClick(findChild(t.a, "settingsPage_shelf"));
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
