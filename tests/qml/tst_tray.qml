import QtQuick
import QtTest
import qs.common
import qs.bar
import "../qs/bar/TrayModel.js" as TrayModel

// App indicators (plan 2.10, D61): which tray items show, the pill's clicks, and a tray menu's entries,
// keyboard and submenus. Tray items are stand-ins with SystemTrayItem's properties and functions.
TestCase {
    id: root
    name: "Tray"
    width: 600
    height: 500
    visible: true
    when: windowShown

    // stand-in enums: Status and QsMenuButtonType's values
    readonly property int passive: 0
    readonly property int active: 1
    readonly property int attention: 2
    readonly property var buttons: ({ checkBox: 1, radioButton: 2 })

    Component {
        id: itemComp
        QtObject {
            property string id: ""
            property string title: ""
            property string tooltipTitle: ""
            property string icon: ""
            property int status: 1
            property bool hasMenu: true
            property bool onlyMenu: false
            property var calls: []
            function activate() { calls = calls.concat(["activate"]); }
            function secondaryActivate() { calls = calls.concat(["secondary"]); }
            function scroll(delta, horizontal) { calls = calls.concat(["scroll " + delta + " " + horizontal]); }
        }
    }
    Component { id: pillComp; TrayPill {} }
    Component { id: panelComp; TrayMenuPanel {} }
    Component { id: spyComp; SignalSpy {} }

    function tray(specs) {
        return specs.map(s => createTemporaryObject(itemComp, root, s));
    }

    // ---- TrayModel ----
    function test_passive_items_are_hidden() {
        const items = tray([{ id: "discord", title: "Discord" }, { id: "idle", status: passive },
                            { id: "steam", tooltipTitle: "Steam", title: "steam", status: attention }]);
        const s = TrayModel.shown(items, passive, attention);
        compare(s.map(e => e.id).join(), "discord,steam", "Passive: nothing to show (the SNI spec)");
        compare(s[1].title, "Steam", "the tooltip's title when there is one");
        verify(s[1].attention);
        verify(!s[0].attention);
        compare(s[0].item, items[0]);
        compare(TrayModel.shown([], passive, attention).length, 0);
    }

    function test_menu_entries() {
        const list = [{ isSeparator: true }, { text: "Open", enabled: true, icon: "image://icon/x" },
                      { isSeparator: true }, { isSeparator: true },
                      { text: "Mute", buttonType: 1, checkState: Qt.Checked },
                      { text: "Online", buttonType: 2, checkState: Qt.Unchecked, enabled: false },
                      { text: "More", hasChildren: true }, { text: "A__B" }, { isSeparator: true }];
        const e = TrayModel.entries(list, buttons, Qt.Checked);
        compare(e.map(x => x.separator ? "-" : x.text).join("|"), "Open|-|Mute|Online|More|A__B",
                "separators not first, last or doubled; underscores kept (Quickshell removed the mnemonics)");
        compare(e[0].id, "1", "the index among the menu's children");
        compare(e[0].image, "image://icon/x");
        compare(e[2].check, "checkbox");
        verify(e[2].checked);
        compare(e[3].check, "radio");
        verify(!e[3].checked);
        verify(e[3].enabled === false);
        verify(e[4].submenu);
        compare(e[5].check, "");
        const plain = TrayModel.entries([{ text: "x", checkState: Qt.Checked }], buttons, Qt.Checked)[0];
        verify(!plain.checked, "a check state without a check or radio button is not shown");
    }

    function test_keyboard_order() {
        const items = [{ id: "a" }, { separator: true }, { id: "b", enabled: false }, { id: "c" }];
        compare(TrayModel.next(items, -1, 1), 0);
        compare(TrayModel.next(items, 0, 1), 3, "separators and disabled entries skipped");
        compare(TrayModel.next(items, 3, 1), 0, "wraps");
        compare(TrayModel.next(items, -1, -1), 3, "up first: the last");
        compare(TrayModel.next(items, 0, -1), 3);
        compare(TrayModel.next([{ separator: true }], -1, 1), -1);
    }

    // ---- TrayPill ----
    function test_pill_only_with_items() {
        const p = createTemporaryObject(pillComp, root, { items: [] });
        verify(!p.visible);
        compare(p.width, 0, "no room taken");
        const items = tray([{ id: "a" }, { id: "b" }]);
        p.items = TrayModel.shown(items, passive, attention);
        verify(p.visible);
        waitForRendering(p);                // a Row lays out at polish
        verify(p.width > 2 * Spacing.lg);
        verify(findChild(p, "trayItem_a") && findChild(p, "trayItem_b"));
        verify(!findChild(findChild(p, "trayItem_a"), "trayAttention").visible, "no dot without a request");
    }

    function test_pill_clicks() {
        const items = tray([{ id: "a" }, { id: "menuOnly", onlyMenu: true }, { id: "noMenu", hasMenu: false }]);
        const p = createTemporaryObject(pillComp, root, { items: TrayModel.shown(items, passive, attention) });
        const menu = createTemporaryObject(spyComp, root, { target: p, signalName: "menuRequested" });
        waitForRendering(p);
        const a = findChild(p, "trayItem_a");
        mouseClick(a);
        compare(items[0].calls.join(), "activate", "a click activates");
        mouseClick(a, a.width / 2, a.height / 2, Qt.MiddleButton);
        compare(items[0].calls.join(), "activate,secondary");
        mouseClick(a, a.width / 2, a.height / 2, Qt.RightButton);
        compare(menu.count, 1, "a right click: its menu");
        compare(menu.signalArguments[0][0].id, "a");
        compare(menu.signalArguments[0][1], a.x + a.width + Spacing.xs, "the icon's right edge, in the pill");
        compare(p.rightOf("a"), a.x + a.width + Spacing.xs);
        compare(p.rightOf("nope"), -1);
        mouseWheel(a, a.width / 2, a.height / 2, 0, 120);
        compare(items[0].calls[2], "scroll 120 false");
        mouseClick(findChild(p, "trayItem_menuOnly"));
        compare(menu.count, 2, "an item with only a menu: a click opens it");
        compare(items[1].calls.length, 0);
        const noMenu = findChild(p, "trayItem_noMenu");
        mouseClick(noMenu, noMenu.width / 2, noMenu.height / 2, Qt.RightButton);
        compare(menu.count, 2, "no menu, nothing to open");
    }

    function test_attention_dot() {
        const items = tray([{ id: "a", status: attention }]);
        const p = createTemporaryObject(pillComp, root, { items: TrayModel.shown(items, passive, attention) });
        verify(findChild(findChild(p, "trayItem_a"), "trayAttention").visible);
    }

    // ---- TrayMenuPanel ----
    function test_menu_choose_and_keyboard() {
        const entries = TrayModel.entries([{ text: "Open" }, { isSeparator: true }, { text: "Off", enabled: false },
                                           { text: "Quit" }], buttons, Qt.Checked);
        const m = createTemporaryObject(panelComp, root, { entries: entries });
        const chosen = createTemporaryObject(spyComp, root, { target: m, signalName: "chosen" });
        const close = createTemporaryObject(spyComp, root, { target: m, signalName: "closeRequested" });
        waitForRendering(m);
        verify(findChild(m, "trayEntry_0"));
        verify(!findChild(m, "trayEntry_2").enabled, "disabled entries grey out");
        mouseClick(findChild(m, "trayEntry_3"));
        compare(chosen.count, 1);
        compare(chosen.signalArguments[0][0], "3", "the index among the menu's children");
        mouseClick(findChild(m, "trayEntry_2"));
        compare(chosen.count, 1, "a disabled entry does nothing");
        m.choose(2);
        m.choose(1);
        compare(chosen.count, 1, "nor when chosen otherwise (IPC, a stale keyboard index), nor a separator");
        m.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(m.menu.currentIndex, 0);
        keyClick(Qt.Key_Down);
        compare(m.menu.currentIndex, 3, "separator and disabled entry skipped");
        keyClick(Qt.Key_Return);
        compare(chosen.signalArguments[1][0], "3");
        keyClick(Qt.Key_Escape);
        compare(close.count, 1);
    }

    function test_submenu_back_row() {
        const m = createTemporaryObject(panelComp, root, { entries: TrayModel.entries([{ text: "More", hasChildren: true }], buttons, Qt.Checked) });
        const back = createTemporaryObject(spyComp, root, { target: m, signalName: "back" });
        const chosen = createTemporaryObject(spyComp, root, { target: m, signalName: "chosen" });
        verify(!findChild(m, "trayEntry_back"), "no Back row at the top level");
        m.forceActiveFocus();
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Right);
        compare(chosen.count, 1, "Right goes into a submenu");
        keyClick(Qt.Key_Left);
        compare(back.count, 0, "nothing to go back to");
        m.depth = 1;
        m.title = "More";
        m.entries = TrayModel.entries([{ text: "Inner" }], buttons, Qt.Checked);
        waitForRendering(m);
        compare(m.menu.currentIndex, -1, "a new list: nothing chosen yet");
        const row = findChild(m, "trayEntry_back");
        verify(row);
        compare(row.text, "More", "the Back row names the submenu");
        mouseClick(row);
        compare(back.count, 1);
        keyClick(Qt.Key_Backspace);
        compare(back.count, 2);
    }

    // separators split the menu into segmented groups: each group's ends get the outer corners
    function test_groups_between_separators() {
        const m = createTemporaryObject(panelComp, root, { entries: TrayModel.entries(
            [{ text: "a" }, { text: "b" }, { isSeparator: true }, { text: "c" }, { isSeparator: true },
             { text: "d" }, { text: "e" }, { text: "f" }], buttons, Qt.Checked) });
        compare(m.menu.positions.join(), "first,last,,single,,first,middle,last");
    }

    function test_check_marks_and_submenu_arrow() {
        const m = createTemporaryObject(panelComp, root, { entries: TrayModel.entries(
            [{ text: "Mute", buttonType: 1, checkState: Qt.Checked }, { text: "More", hasChildren: true },
             { text: "Plain" }], buttons, Qt.Checked) });
        waitForRendering(m);
        function trailing(id) {
            const item = findChild(m, "trayEntry_" + id);
            const icons = [];
            (function walk(n) {
                if (n.name !== undefined && n.fill !== undefined && n.visible) icons.push(n.name);
                for (const c of n.children) walk(c);
            })(item);
            return icons.join();
        }
        compare(trailing("0"), "check_box");
        compare(trailing("1"), "chevron_right");
        compare(trailing("2"), "");
    }

    function test_motion_and_hidden() {
        const m = createTemporaryObject(panelComp, root, { entries: [{ id: "0", text: "x" }] });
        const hidden = createTemporaryObject(spyComp, root, { target: m, signalName: "hidden" });
        m.shown = false;
        tryCompare(hidden, "count", 1, 2000);
    }
}
