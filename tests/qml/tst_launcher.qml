import QtQuick
import QtTest
import qs.common
import qs.launcher
import "../qs/launcher/Scorer.js" as Scorer
import "../qs/launcher/Categories.js" as Categories
import "../qs/launcher/Usage.js" as Usage
import "../qs/quicksettings/Controls.js" as Controls

TestCase {
    id: root
    name: "Launcher"
    width: 800
    height: 800
    visible: true
    when: windowShown

    readonly property var apps: [
        { type: "app", id: "org.gnome.Nautilus", name: "Files", genericName: "File Manager", keywords: ["folder", "explorer"], subtitle: "Access and organize files", icon: "", categories: ["GNOME", "Utility", "FileManager"] },
        { type: "app", id: "firefox", name: "Firefox", genericName: "Web Browser", keywords: ["internet"], subtitle: "", icon: "", categories: ["Network", "WebBrowser"],
          actions: [{ id: "new-window", name: "New Window" }, { id: "new-private-window", name: "New Private Window" }] },
        { type: "app", id: "code", name: "Visual Studio Code", genericName: "Text Editor", keywords: [], subtitle: "", icon: "", categories: ["Development", "IDE"] },
        { type: "app", id: "foot", name: "Foot", genericName: "Terminal", keywords: ["shell"], subtitle: "", icon: "", categories: ["System", "TerminalEmulator"] },
        { type: "app", id: "firewall", name: "Firewall", genericName: "", keywords: [], subtitle: "Network rules", icon: "", categories: ["System", "Settings"] }
    ]
    function ids(list) { return list.map(a => a.id).join(); }
    function cleanup() { Motion.speed = 1; }   // a test that slows the motion and fails leaves it as it was

    Component { id: panelComp; LauncherPanel { apps: root.apps } }

    // A Quick Settings backend as Controls.js reads it: records what it is asked.
    Component {
        id: backendComp
        QtObject {
            property bool wifiAvailable: true
            property bool wifiEnabled: true
            property string wifiName: "home"
            property bool bluetoothAvailable: false
            property bool bluetoothEnabled: false
            property string bluetoothDevice: ""
            property bool micAvailable: true
            property bool micMuted: true
            property bool darkTheme: false
            property bool brightnessAvailable: true
            property real brightness: 0.404
            property bool volumeAvailable: true
            property real volume: 0.5
            property bool muted: false
            property var asked: []
            function setWifiEnabled(on) { asked.push("wifi " + on); wifiEnabled = on; }
            function setBluetoothEnabled(on) { asked.push("bluetooth " + on); }
            function setMicMuted(m) { asked.push("micMuted " + m); micMuted = m; }
            function setDarkTheme(on) { asked.push("dark " + on); darkTheme = on; }
            function setAirplaneMode(on) { asked.push("airplane " + on); }
        }
    }
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
        Motion.speed = 0.2;
        keyClick(Qt.Key_Backtab);
        compare(p.category, "utilities");
        var last = findChild(p, "launcherChip_utilities");
        tryVerify(() => chips.contentX > 0 && chips.contentX < chips.contentWidth - chips.width - 1, 2000,
                  "scrolls, not jumps (in slow motion, so a busy machine still sees it in flight)");
        Motion.speed = 1;
        var all = findChild(p, "launcherChip_all");
        tryVerify(() => Math.abs(last.width - last.implicitWidth) < 0.01 && last.leadingShown === 1
                  && all.leadingShown === 0, 3000, "the check marks settle");
        waitForRendering(chips);
        compare(last.x + last.width, chips.contentWidth, "placed again with its check mark");
        tryVerify(() => chips.contentX === chips.contentWidth - chips.width, 3000, "the last chip in view, not past it");
        keyClick(Qt.Key_Tab);
        tryCompare(chips, "contentX", 0, 3000, "All back in view");
        // the row's layout from that step must be done, or its late reveal of All pulls the row back (seen under load)
        tryVerify(() => all.leadingShown === 1 && last.leadingShown === 0
                  && Math.abs(all.width - all.implicitWidth) < 0.01 && Math.abs(last.width - last.implicitWidth) < 0.01,
                  3000, "the check marks settle again");
        waitForRendering(chips);
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

    function test_app_menu_by_mouse() {
        var p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        var launched = createTemporaryObject(spyComp, root, { target: p, signalName: "launched" });
        var action = createTemporaryObject(spyComp, root, { target: p, signalName: "actionChosen" });
        var tile = findChild(p, "launcherApp_firefox");
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton);
        verify(p.menuOpen);
        compare(launched.count, 0, "a right click does not launch");
        compare(p.currentIndex, 1, "and makes it the current app");
        compare(p.menuItems[0].icon, "", "no icons: the entries line up");
        compare(p.menuItems.map(i => i.text).join(), "Open,New Window,New Private Window,Pin to shelf");
        tryVerify(() => p.menu && p.menu.scale === 1, 2000, "grows in");
        var loader = findChild(p, "launcherMenu");
        verify(loader.below, "under a top-row app");
        compare(loader.origin, Item.TopLeft);
        var tileTop = tile.mapToItem(p, 0, 0).y;
        verify(loader.y > tileTop + tile.height / 2 && loader.y < tileTop + tile.height, "hangs from its lower part");
        verify(loader.x >= Spacing.sm && loader.x + loader.width <= p.width - Spacing.sm, "inside the panel");
        compare(findChild(p.menu, "launcherMenu_").selected, true, "Open is the keyboard's choice");
        var item = findChild(p.menu, "launcherMenu_new-private-window");
        mouseClick(item, item.width / 2, item.height / 2);
        compare(action.count, 1);
        compare(action.signalArguments[0][0].id, "firefox");
        compare(action.signalArguments[0][1], "new-private-window");
        verify(!p.menuOpen, "choosing closes it");
        tryVerify(() => !findChild(p, "launcherMenu").item, 2000, "and unloads it after its motion");
        // a press outside closes it and goes no further
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton);
        verify(p.menuOpen);
        var other = findChild(p, "launcherApp_foot");
        mouseClick(other, other.width / 2, other.height / 2);
        verify(!p.menuOpen);
        compare(launched.count, 0, "the press only closed the menu");
        // Open launches the app
        mouseClick(other, other.width / 2, other.height / 2, Qt.RightButton);
        compare(p.menuItems.map(i => i.text).join(), "Open,Pin to shelf", "no desktop actions");
        tryVerify(() => p.menu && p.menu.scale === 1, 2000);
        item = findChild(p.menu, "launcherMenu_");
        mouseClick(item, item.width / 2, item.height / 2);
        compare(launched.count, 1);
        compare(launched.signalArguments[0][0].id, "foot");
    }

    function test_usage_record() {
        const day = 24 * 60 * 60 * 1000;
        let u = Usage.record({}, "foot", 1000);
        compare(JSON.stringify(u), '{"foot":{"count":1,"last":1000}}');
        const before = u;
        u = Usage.record(u, "foot", 2000);
        compare(u.foot.count + "," + u.foot.last, "2,2000", "counts up, last is the latest");
        compare(before.foot.count, 1, "the original is not changed");
        u = Usage.record(u, "firefox", 3000);
        compare(u.foot.count + "," + u.firefox.count, "2,1", "apps apart");
        compare(Usage.record({ x: { count: "bad" } }, "x", 1).x.count, 1, "a bad count starts over");
        compare(Usage.record({ x: { count: -3 } }, "x", 1).x.count, 1);
        // past the limit the least recently used go
        let many = {};
        for (let i = 0; i < Usage.maxApps; i++) many["a" + i] = { count: 5, last: 100 + i };
        u = Usage.record(many, "new", 10 * day);
        compare(Object.keys(u).length, Usage.maxApps);
        verify(!("a0" in u), "the oldest went");
        verify("a1" in u && "new" in u, "the rest stay");
        compare(Object.keys(Usage.record(many, "a5", 10 * day)).length, Usage.maxApps, "a known app adds none");
    }

    function test_usage_score() {
        const day = 24 * 60 * 60 * 1000;
        const now = 1000 * day;
        compare(Usage.score(undefined, now), 0);
        compare(Usage.score({ count: 0, last: now }, now), 0);
        compare(Usage.score({ count: "x", last: now }, now), 0);
        compare(Usage.score({ count: 10, last: now }, now), 10, "today: full");
        compare(Usage.score({ count: 10, last: now - 4 * day + 1 }, now), 10);
        compare(Usage.score({ count: 10, last: now - 4 * day }, now), 7, "from four days");
        compare(Usage.score({ count: 10, last: now - 14 * day }, now), 5, "two weeks");
        compare(Usage.score({ count: 10, last: now - 31 * day }, now), 3, "a month");
        compare(Usage.score({ count: 10, last: now - 90 * day }, now), 1, "three months and older");
        compare(Usage.score({ count: 10 }, now), 1, "no date: old");
    }

    function test_usage_ranks_search_results() {
        const now = Date.now();
        var p = createTemporaryObject(panelComp, root, { now: now });
        p.query = "fire";
        compare(ids(p.results).split(",").slice(0, 2).join(), "firefox,firewall", "without usage: in given order");
        p.usage = { firewall: { count: 3, last: now } };
        compare(p.results[0].id, "firewall", "the used one first");
        p.usage = { firewall: { count: 3, last: now - 400 * 24 * 60 * 60 * 1000 } };
        compare(p.results[0].id, "firewall", "an old use still counts a little");
        p.usage = { "org.gnome.Nautilus": { count: 1000, last: now } };
        compare(p.results[0].id, "firefox", "usage does not lift a typo match over a prefix match");
        p.query = "";
        p.usage = { foot: { count: 50, last: now } };
        compare(ids(p.results), "org.gnome.Nautilus,firefox,firewall,foot,code", "no query: name order, usage or not");
    }

    function test_app_menu_pin() {
        var p = createTemporaryObject(panelComp, root, { pinnedIds: ["foot"] });
        waitForRendering(p);
        var pin = createTemporaryObject(spyComp, root, { target: p, signalName: "pinToggled" });
        var launched = createTemporaryObject(spyComp, root, { target: p, signalName: "launched" });
        var tile = findChild(p, "launcherApp_foot");
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton);
        compare(p.menuItems.map(i => i.text).join(), "Open,Unpin from shelf", "a pinned app");
        tryVerify(() => p.menu && p.menu.scale === 1, 2000);
        var item = findChild(p.menu, "launcherMenu_rutile:pin");
        mouseClick(item, item.width / 2, item.height / 2);
        compare(pin.count, 1);
        compare(pin.signalArguments[0][0].id, "foot");
        compare(launched.count, 0, "pinning does not launch");
        verify(!p.menuOpen);
        tile = findChild(p, "launcherApp_firefox");
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton);
        compare(p.menuItems[p.menuItems.length - 1].text, "Pin to shelf", "an app not pinned");
        p.menuOpen = false;
        p.pinsEditable = false;
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton);
        compare(p.menuItems.map(i => i.text).join(), "Open,New Window,New Private Window", "pins set in Nix: no entry");
    }

    function test_app_menu_by_keyboard() {
        failOnWarning(/TypeError/);
        var p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        var launched = createTemporaryObject(spyComp, root, { target: p, signalName: "launched" });
        var action = createTemporaryObject(spyComp, root, { target: p, signalName: "actionChosen" });
        var close = createTemporaryObject(spyComp, root, { target: p, signalName: "closeRequested" });
        keyClick(Qt.Key_Right);             // Firefox
        keyClick(Qt.Key_Menu);
        verify(p.menuOpen);
        compare(p.menuApp.id, "firefox", "the current app's menu");
        keyClick(Qt.Key_Right); keyClick(Qt.Key_Left); keyClick(Qt.Key_Tab); keyClick(Qt.Key_Backtab);
        compare(p.currentIndex, 1, "the arrows and Tab stay in the menu");
        compare(p.category, "");
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Down); keyClick(Qt.Key_Down); keyClick(Qt.Key_Down);
        compare(p.menuIndex, 3, "down to the last (Pin to shelf), no further");
        keyClick(Qt.Key_Up);
        compare(p.menuIndex, 2);
        keyClick(Qt.Key_Escape);
        verify(!p.menuOpen, "Escape closes the menu");
        compare(close.count, 0, "but not the launcher");
        keyClick(Qt.Key_F10);
        verify(!p.menuOpen, "F10 alone does not");
        keyClick(Qt.Key_F10, Qt.ShiftModifier);
        verify(p.menuOpen, "Shift+F10 opens it too");
        compare(p.menuIndex, 0, "from the top again");
        keyClick(Qt.Key_Up);
        compare(p.menuIndex, 0, "no further up");
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        compare(action.count, 1);
        compare(action.signalArguments[0][1], "new-window");
        compare(launched.count, 0);
        keyClick(Qt.Key_Menu);
        keyClick(Qt.Key_Enter);
        compare(launched.count, 1, "Open");
        compare(launched.signalArguments[0][0].id, "firefox");
        keyClick(Qt.Key_Menu);
        keyClick(Qt.Key_Menu);
        verify(!p.menuOpen, "the Menu key closes it again");
        keyClick(Qt.Key_F10, Qt.ShiftModifier);
        keyClick(Qt.Key_F10, Qt.ShiftModifier);
        verify(!p.menuOpen, "so does Shift+F10");
        keyClick(Qt.Key_Menu);
        keyClick(Qt.Key_F);
        verify(!p.menuOpen, "typing closes it");
        compare(p.query, "f", "and goes into the field");
        keyClick(Qt.Key_Menu);
        p.listView = true;
        verify(!p.menuOpen, "so does a view change");
        keyClick(Qt.Key_Menu);
        p.category = "system";
        verify(!p.menuOpen, "and a chip");
        p.query = "qqqq";
        keyClick(Qt.Key_Menu);
        verify(!p.menuOpen, "no app, no menu");
    }

    function test_app_menu_in_the_list() {
        var p = createTemporaryObject(panelComp, root, { listView: true });
        waitForRendering(p);
        var row = findChild(p, "launcherApp_firefox");
        mouseClick(row, row.width - 20, row.height / 2, Qt.RightButton);
        tryVerify(() => p.menu && p.menu.scale === 1, 2000);
        var loader = findChild(p, "launcherMenu");
        compare(loader.x, row.mapToItem(p, p.cell / 2, 0).x, "near the row's icon, not its middle");
    }

    function test_app_menu_opens_above_the_bottom_rows() {
        var many = [];
        for (var i = 0; i < 20; i++) many.push({ type: "app", id: "a" + i, name: "App " + String(i).padStart(2, "0") });
        var p = createTemporaryObject(panelComp, root, { apps: many });
        waitForRendering(p);
        var tile = findChild(p, "launcherApp_a19");
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton);
        tryVerify(() => p.menu && p.menu.scale === 1, 2000);
        var loader = findChild(p, "launcherMenu");
        verify(!loader.below, "no room under the last row");
        compare(loader.origin, Item.BottomLeft);
        var top = tile.mapToItem(p, 0, 0).y;
        verify(loader.y + loader.height > top && loader.y + loader.height < top + tile.height / 2, "hangs above it");
        verify(loader.x + loader.width <= p.width - Spacing.sm, "pulled in from the right edge");
        verify(loader.x < tile.mapToItem(p, tile.width / 2, 0).x, "so it starts left of the app's middle");
    }

    function test_empty_states() {
        var none = createTemporaryObject(panelComp, root, { apps: [] });
        waitForRendering(none);
        compare(none.results.length, 0);
        compare(none.currentIndex, -1);
    }

    function test_controls_search_items() {
        const b = createTemporaryObject(backendComp, root);
        let items = Controls.searchItems(b);
        compare(items.map(i => i.id).join(), "qs:wifi,qs:mic,qs:dark,qs:airplane,qs:brightness,qs:volume",
                "only what this system has (no Bluetooth)");
        const wifi = items[0];
        compare(wifi.type, "setting");
        compare(wifi.control + "," + wifi.action + "," + wifi.name, "wifi,toggle,Wi-Fi");
        compare(wifi.symbol + "," + wifi.status, "wifi,home", "on: its icon and the network");
        verify(wifi.keywords.indexOf("wireless") >= 0);
        const mic = items[1];
        compare(mic.symbol + "," + mic.status, "mic_off,Muted", "off: the off icon");
        compare(items[3].status, "Off", "airplane mode is off while Wi-Fi is on");
        compare(items[4].action + "," + items[4].status + "," + items[4].symbol, "open,40%,brightness_medium");
        compare(items[5].action + "," + items[5].status + "," + items[5].symbol, "open,50%,music_note");
        b.muted = true;
        b.brightnessAvailable = false;
        b.volumeAvailable = false;
        b.wifiAvailable = false;
        items = Controls.searchItems(b);
        compare(items.map(i => i.id).join(), "qs:mic,qs:dark", "no radios, no backlight, no audio");
        b.volumeAvailable = true;
        compare(Controls.searchItems(b).pop().status + "," + Controls.searchItems(b).pop().symbol, "Muted,music_off");
        compare(Controls.searchItems(null).length, 0);
    }

    function test_controls_choose() {
        const b = createTemporaryObject(backendComp, root);
        const items = Controls.searchItems(b);
        compare(Controls.choose(items[0], b), "toggled");
        compare(b.asked.join(), "wifi false", "Wi-Fi was on: off");
        compare(Controls.choose(items[1], b), "toggled");
        compare(b.asked[1], "micMuted false", "the muted microphone: on");
        compare(Controls.choose(items[2], b), "toggled");
        compare(b.asked[2], "dark true");
        compare(Controls.choose(items[4], b), "open", "a slider: Quick Settings opens");
        compare(Controls.choose(items[5], b), "open");
        compare(b.asked.length, 3, "and nothing else was asked");
    }

    function test_settings_results() {
        const b = createTemporaryObject(backendComp, root);
        var p = createTemporaryObject(panelComp, root, { settings: Controls.searchItems(b) });
        waitForRendering(p);
        var chosen = createTemporaryObject(spyComp, root, { target: p, signalName: "settingChosen" });
        var launched = createTemporaryObject(spyComp, root, { target: p, signalName: "launched" });
        compare(ids(p.results), "org.gnome.Nautilus,firefox,firewall,foot,code", "no query: apps only");
        p.query = "wifi";
        compare(p.results[0].id, "qs:wifi", "found by name");
        p.query = "wireless";
        compare(p.results[0].id, "qs:wifi", "and by keyword");
        p.query = "home";
        verify(p.results.every(r => r.id !== "qs:wifi"), "not by its status");
        p.query = "fire";
        compare(ids(p.results).split(",").slice(0, 2).join(), "firefox,firewall", "apps as before");
        p.query = "dark";
        p.category = "system";
        compare(p.results.length, 0, "a category shows only apps");
        p.category = "";
        compare(p.results[0].id, "qs:dark");
        // Enter chooses it; the app menu is not offered
        keyClick(Qt.Key_Return);
        compare(chosen.count, 1);
        compare(chosen.signalArguments[0][0].id, "qs:dark");
        compare(launched.count, 0, "not launched as an app");
        p.toggleMenu();
        verify(!p.menuOpen, "no menu for a setting");
        var tile = findChild(p, "launcherApp_qs:dark");
        verify(findChild(tile, "launcherTileSymbol").item, "a symbol");
        verify(!findChild(tile, "launcherTileInitial").visible, "not an initial");
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton);
        verify(!p.menuOpen, "a right click neither");
        mouseClick(tile, tile.width / 2, tile.height / 2);
        compare(chosen.count, 2, "a click chooses it too");
        p.listView = true;
        tryVerify(() => findChild(findChild(p, "launcherApp_qs:dark"), "launcherTileSubtitle")?.text === "Off", 2000,
                  "the list shows its state");
        p.query = "fire";
        var app = findChild(p, "launcherApp_firefox");
        verify(!findChild(app, "launcherTileSymbol").item, "an app has no symbol");
    }
}
