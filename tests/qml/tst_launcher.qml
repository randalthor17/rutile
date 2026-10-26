import QtQuick
import QtTest
import qs.common
import qs.launcher
import "../qs/launcher/Scorer.js" as Scorer
import "../qs/launcher/Categories.js" as Categories

TestCase {
    id: root
    name: "Launcher"
    width: 800
    height: 800
    visible: true
    when: windowShown

    readonly property var apps: [
        { type: "app", id: "org.gnome.Nautilus", name: "Files", genericName: "File Manager", keywords: ["folder", "explorer"], subtitle: "Access and organize files", icon: "", categories: ["GNOME", "Utility", "FileManager"] },
        { type: "app", id: "firefox", name: "Firefox", genericName: "Web Browser", keywords: ["internet"], subtitle: "", icon: "", categories: ["Network", "WebBrowser"] },
        { type: "app", id: "code", name: "Visual Studio Code", genericName: "Text Editor", keywords: [], subtitle: "", icon: "", categories: ["Development", "IDE"] },
        { type: "app", id: "foot", name: "Foot", genericName: "Terminal", keywords: ["shell"], subtitle: "", icon: "", categories: ["System", "TerminalEmulator"] },
        { type: "app", id: "firewall", name: "Firewall", genericName: "", keywords: [], subtitle: "Network rules", icon: "", categories: ["System", "Settings"] }
    ]
    function ids(list) { return list.map(a => a.id).join(); }

    Component { id: panelComp; LauncherPanel { apps: root.apps } }
    Component { id: spyComp; SignalSpy {} }

    function test_ranking() {
        compare(ids(Scorer.rank(apps, "")), "org.gnome.Nautilus,firefox,firewall,foot,code", "no query: every app, by name");
        compare(ids(Scorer.rank(apps, "firefox")), "firefox", "exact");
        compare(ids(Scorer.rank(apps, "fire").slice(0, 2)), "firefox,firewall", "prefix, ties in given order");
        compare(Scorer.rank(apps, "fire")[2].id, "org.gnome.Nautilus", "then Files, two letters off (DMS's fuzzy match)");
        compare(Scorer.rank(apps, "Firew")[0].id, "firewall", "case does not matter");
        compare(Scorer.rank(apps, "vis stu")[0].id, "code", "word starts");
        compare(Scorer.rank(apps, "studio")[0].id, "code", "a later word");
        compare(Scorer.rank(apps, "browser")[0].id, "firefox", "the generic name");
        compare(Scorer.rank(apps, "folder")[0].id, "org.gnome.Nautilus", "a keyword");
        compare(Scorer.rank(apps, "organize")[0].id, "org.gnome.Nautilus", "the subtitle");
        compare(Scorer.rank(apps, "nautilus")[0].id, "org.gnome.Nautilus", "the desktop id");
        compare(Scorer.rank(apps, "firfox")[0].id, "firefox", "a typo");
        compare(Scorer.rank(apps, "zzzz").length, 0, "nothing matches");
        verify(Scorer.score(apps[1], "firefox", 0) > Scorer.score(apps[1], "fire", 0), "exact beats prefix");
        compare(Scorer.textScore("studio manager", "stu"), Scorer.Weights.prefixMatch);
        verify(Scorer.rank([apps[2], { type: "app", id: "sm", name: "Studio Manager" }], "stu")[0].id === "sm",
               "a prefix beats a later word start");
        verify(Scorer.score(apps[1], "fire", 5) > Scorer.score(apps[1], "fire", 0), "usage counts");
        compare(Scorer.levenshteinDistance("kitten", "sitting"), 3);
        // the letters in order, from a word start: "nvi" finds Neovide as well as Neovim
        var editors = [{ type: "app", id: "nvim", name: "Neovim wrapper" }, { type: "app", id: "neovide", name: "Neovide" },
                       { type: "app", id: "vim", name: "Vim" }, { type: "app", id: "unveil", name: "Unveil" }];
        compare(ids(Scorer.rank(editors, "nvi")), "nvim,neovide", "Unveil: its n starts no word");
        compare(Scorer.subsequenceScore("neovide", "nvi"), 3 / 5);
        compare(Scorer.subsequenceScore("neovide", "evi"), 0, "the first letter starts a word");
        compare(Scorer.subsequenceScore("a.neovide", "nvi"), 3 / 5, "a dot separates words");
        compare(Scorer.subsequenceScore("neovide", "n"), 0, "one letter is not enough");
        compare(Scorer.subsequenceScore("ab", "ab"), 1);
        compare(Scorer.subsequenceScore("nx", "nn"), 0, "each letter is used once");
        compare(Scorer.subsequenceScore("nx neovide", "nvi"), 3 / 5, "a later word start");
        compare(Scorer.subsequenceScore("nvi nxxvi", "nvi"), 1, "the densest start wins, not the last");
        compare(Scorer.subsequenceScore("nabcdefghiv i", "nvi"), 0, "too spread out: span 13 over 9");
        compare(Scorer.subsequenceScore("nabcdefvi", "nvi"), 1 / 3, "span 9 is still in");
        verify(Scorer.score(editors[0], "neo", 0) > Scorer.score(editors[0], "nvi", 0), "a prefix beats letters in order");
        verify(Scorer.hasWordBoundaryMatch("visual studio code", "stu co"));
        verify(!Scorer.hasWordBoundaryMatch("visual studio code", "code vis"));
    }

    function test_categories() {
        compare(Categories.present(apps).map(c => c.id).join(), "internet,development,system,utilities", "chip order, only used ones");
        compare(ids(Categories.filter(apps, "system")), "foot,firewall");
        compare(ids(Categories.filter(apps, "")), ids(apps), "All");
        verify(!Categories.matches(apps[0], "nope"));
        verify(!Categories.matches({ id: "x" }, "system"), "no categories at all");
        compare(Categories.present([]).length, 0);
    }

    function test_chips_filter_the_results() {
        var p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        var field = findChild(p, "launcherSearch");
        compare(ids(p.categories), "internet,development,system,utilities");
        verify(findChild(p, "launcherChip_all").selected, "All to start");
        keyClick(Qt.Key_Tab);
        compare(p.category, "internet");
        compare(ids(p.results), "firefox");
        keyClick(Qt.Key_Tab); keyClick(Qt.Key_Tab);
        compare(p.category, "system");
        compare(ids(p.results), "firewall,foot", "by name");
        verify(findChild(p, "launcherChip_system").selected);
        verify(!findChild(p, "launcherChip_all").selected);
        keyClick(Qt.Key_F);
        compare(ids(p.results), "foot,firewall", "the search ranks within the chip (prefix ties: given order)");
        keyClick(Qt.Key_I);
        compare(ids(p.results), "firewall");
        keyClick(Qt.Key_Backtab);
        compare(p.category, "development");
        compare(p.results.length, 0, "fi: nothing in development");
        keyClick(Qt.Key_Tab); keyClick(Qt.Key_Tab); keyClick(Qt.Key_Tab);
        compare(p.category, "", "wraps to All");
        keyClick(Qt.Key_Backtab);
        compare(p.category, "utilities", "and back");
        p.category = "games";               // a chip that is not there (no games): Tab starts from All
        keyClick(Qt.Key_Tab);
        compare(p.category, "internet");
        verify(field.activeFocus, "the field keeps the keyboard");
        p.query = "";
        p.category = "";
        var chip = findChild(p, "launcherChip_internet");
        mouseClick(chip, chip.width / 2, chip.height / 2);
        compare(p.category, "internet");
        mouseClick(chip, chip.width / 2, chip.height / 2);
        compare(p.category, "", "clicking the chosen chip goes back to All");
        chip = findChild(p, "launcherChip_all");
        mouseClick(chip, chip.width / 2, chip.height / 2);
        compare(p.category, "", "All stays chosen");
        verify(field.activeFocus, "still typing into the field");
    }

    function test_results_fade_in_on_a_chip_or_view_change() {
        var p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        var grid = findChild(p, "launcherGrid");
        compare(grid.opacity, 1);
        keyClick(Qt.Key_F);
        compare(grid.opacity, 1, "typing does not fade");
        keyClick(Qt.Key_Tab);
        verify(grid.opacity < 0.5, "a chip change starts from faded");
        tryCompare(grid, "opacity", 1, 2000);
        p.listView = true;
        verify(grid.opacity < 0.5, "so does the view toggle");
        tryCompare(grid, "opacity", 1, 2000);
    }

    function test_chips_scroll_into_view() {
        var many = ["Network", "AudioVideo", "Graphics", "Office", "Development", "Game", "Education", "System", "Utility"]
            .map((c, i) => ({ type: "app", id: "a" + i, name: "App " + i, categories: [c] }));
        var p = createTemporaryObject(panelComp, root, { apps: many });
        waitForRendering(p);
        var chips = findChild(p, "launcherChips");
        verify(chips.contentWidth > chips.width, "nine chips overflow");
        compare(chips.contentX, 0);
        keyClick(Qt.Key_Backtab);
        compare(p.category, "utilities");
        var last = findChild(p, "launcherChip_utilities");
        wait(50);
        verify(chips.contentX > 0 && chips.contentX < chips.contentWidth - chips.width - 1, "scrolls, not jumps");
        var all = findChild(p, "launcherChip_all");
        tryVerify(() => Math.abs(last.width - last.implicitWidth) < 0.01 && last.leadingShown === 1
                  && all.leadingShown === 0, 3000, "the check marks settle");
        waitForRendering(chips);
        compare(last.x + last.width, chips.contentWidth, "placed again with its check mark");
        tryVerify(() => chips.contentX === chips.contentWidth - chips.width, 3000, "the last chip in view, not past it");
        keyClick(Qt.Key_Tab);
        tryCompare(chips, "contentX", 0, 3000, "All back in view");
        chips.contentX = 200;               // as the wheel would
        keyClick(Qt.Key_Backtab);
        var lowest = 1e9;
        for (var i = 0; i < 10; i++) {
            wait(16);
            lowest = Math.min(lowest, chips.contentX);
        }
        verify(lowest >= 200, "scrolls on from where the wheel left it, got " + lowest);
        tryVerify(() => chips.contentX === chips.contentWidth - chips.width, 3000, "to the end");
        var end = chips.contentX;
        chips.contentX = 100;               // the wheel again; the row is placed again (the apps changed, say)
        chips.reveal();
        tryCompare(chips, "contentX", end, 3000, "the chosen chip comes back into view");
    }

    function test_list_view() {
        var p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        var field = findChild(p, "launcherSearch");
        var grid = findChild(p, "launcherGrid");
        var toggle = findChild(p, "launcherViewToggle");
        compare(toggle.iconName, "view_list");
        compare(grid.cellWidth, p.cell);
        mouseClick(toggle, toggle.width / 2, toggle.height / 2);
        verify(p.listView);
        compare(toggle.iconName, "grid_view");
        verify(field.activeFocus, "the field keeps the keyboard");
        compare(grid.cellWidth, grid.width, "one app per row");
        compare(grid.cellHeight, p.rowHeight);
        var row = findChild(p, "launcherApp_org.gnome.Nautilus");
        compare(row.width, grid.width);
        compare(row.height, p.rowHeight);
        var sub = findChild(row, "launcherTileSubtitle");
        verify(sub && sub.visible);
        compare(sub.width, row.width - 2 * Spacing.lg - Spacing.xxl - Spacing.lg, "the label's width, after the icon");
        compare(sub.text, "File Manager", "the generic name first");
        compare(findChild(findChild(p, "launcherApp_firewall"), "launcherTileSubtitle").text, "Network rules", "else the comment");
        verify(findChild(findChild(p, "launcherApp_firefox"), "launcherTileSubtitle"));
        keyClick(Qt.Key_Down);
        compare(p.currentIndex, 1, "down is the next app");
        keyClick(Qt.Key_Up);
        compare(p.currentIndex, 0);
        keyClick(Qt.Key_F); keyClick(Qt.Key_O);
        keyClick(Qt.Key_Left);
        compare(field.cursorPosition, 1, "left moves the text cursor in the list");
        keyClick(Qt.Key_Right);
        compare(field.cursorPosition, 2);
        compare(p.currentIndex, 0);
        mouseClick(toggle, toggle.width / 2, toggle.height / 2);
        verify(!p.listView, "and back to the grid");
        tryVerify(() => !findChild(findChild(p, "launcherApp_foot"), "launcherTileSubtitle"), 1000, "no description in the grid");
        var bare = createTemporaryObject(panelComp, root, { apps: [{ type: "app", id: "x", name: "X" }], listView: true });
        waitForRendering(bare);
        verify(findChild(bare, "launcherApp_x"));
        verify(!findChild(findChild(bare, "launcherApp_x"), "launcherTileSubtitle"), "no description: nothing loaded");
    }

    function test_typing_filters_and_enter_launches() {
        var p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        var launched = createTemporaryObject(spyComp, root, { target: p, signalName: "launched" });
        var field = findChild(p, "launcherSearch");
        verify(field.activeFocus, "the field has the keyboard");
        compare(p.results.length, 5);
        compare(p.currentIndex, 0);
        keyClick(Qt.Key_F); keyClick(Qt.Key_I); keyClick(Qt.Key_R);
        compare(p.query, "fir");
        compare(ids(p.results), "firefox,firewall");
        compare(p.currentIndex, 0, "the best match is current");
        keyClick(Qt.Key_Right);         // the arrows move through the grid, not the text
        compare(p.currentIndex, 1);
        keyClick(Qt.Key_Left);
        compare(p.currentIndex, 0);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        compare(launched.count, 1);
        compare(launched.signalArguments[0][0].id, "firewall", "the current app");
        keyClick(Qt.Key_E);             // "fire": still two; the current one goes back to the first
        compare(p.currentIndex, 0);
        keyClick(Qt.Key_W);
        compare(p.results[0].id, "firewall", "Files is still a loose fuzzy match, after it");
        keyClick(Qt.Key_Enter);
        compare(launched.signalArguments[1][0].id, "firewall");
        p.query = "qqqq";
        compare(p.results.length, 0);
        tryCompare(p, "currentIndex", -1, 1000, "no current app without results");
        keyClick(Qt.Key_Return);
        compare(launched.count, 2, "nothing to launch");
    }

    function test_arrows_move_through_the_grid() {
        var p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        compare(p.currentIndex, 0);
        keyClick(Qt.Key_Down);
        compare(p.currentIndex, 0, "one row of five: nowhere to go down");
        keyClick(Qt.Key_Right); keyClick(Qt.Key_Right); keyClick(Qt.Key_Right); keyClick(Qt.Key_Right);
        compare(p.currentIndex, 4);
        keyClick(Qt.Key_Right);
        compare(p.currentIndex, 4, "no wrapping");
        compare(findChild(p, "launcherSearch").cursorPosition, 0, "the text cursor stays");
    }

    function test_click_escape_and_motion() {
        var p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        var launched = createTemporaryObject(spyComp, root, { target: p, signalName: "launched" });
        var close = createTemporaryObject(spyComp, root, { target: p, signalName: "closeRequested" });
        var hidden = createTemporaryObject(spyComp, root, { target: p, signalName: "hidden" });
        compare(p.transformOrigin, Item.Bottom, "grows up from the shelf");
        tryCompare(p, "scale", 1, 2000);
        var tile = findChild(p, "launcherApp_foot");
        verify(tile);
        mouseClick(tile, tile.width / 2, tile.height / 2);
        compare(launched.signalArguments[0][0].id, "foot");
        tryCompare(findChild(findChild(p, "launcherApp_org.gnome.Nautilus"), "launcherTileCurrent"), "opacity", 1, 2000,
                   "the current app is marked");
        compare(findChild(findChild(p, "launcherApp_foot"), "launcherTileCurrent").opacity, 0);
        keyClick(Qt.Key_Escape);
        compare(close.count, 1);
        p.shown = false;
        tryCompare(hidden, "count", 1, 2000);
    }

    function test_empty_states() {
        var none = createTemporaryObject(panelComp, root, { apps: [] });
        waitForRendering(none);
        compare(none.results.length, 0);
        compare(none.currentIndex, -1);
    }
}
