import QtQuick
import QtTest
import qs.common
import qs.launcher
import "../qs/launcher/Scorer.js" as Scorer

TestCase {
    id: root
    name: "Launcher"
    width: 800
    height: 800
    visible: true
    when: windowShown

    readonly property var apps: [
        { type: "app", id: "org.gnome.Nautilus", name: "Files", genericName: "File Manager", keywords: ["folder", "explorer"], subtitle: "Access and organize files", icon: "" },
        { type: "app", id: "firefox", name: "Firefox", genericName: "Web Browser", keywords: ["internet"], subtitle: "", icon: "" },
        { type: "app", id: "code", name: "Visual Studio Code", genericName: "Text Editor", keywords: [], subtitle: "", icon: "" },
        { type: "app", id: "foot", name: "Foot", genericName: "Terminal", keywords: ["shell"], subtitle: "", icon: "" },
        { type: "app", id: "firewall", name: "Firewall", genericName: "", keywords: [], subtitle: "", icon: "" }
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
        verify(Scorer.hasWordBoundaryMatch("visual studio code", "stu co"));
        verify(!Scorer.hasWordBoundaryMatch("visual studio code", "code vis"));
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
