// Wallhaven (D128): the search address and the API's answer (Wallhaven.js), and the browser panel: results as
// thumbnails, a click asks for one, filters and menus ask for a new search, pages, NSFW only with an API key.
import QtQuick
import QtTest
import qs.common
import qs.wallhaven
import "../qs/wallhaven/Wallhaven.js" as Wallhaven

TestCase {
    id: root
    name: "Wallhaven"
    width: 1000
    height: 900
    visible: true
    when: windowShown

    readonly property var results: [
        { id: "abc123", path: "https://w.wallhaven.cc/full/ab/wallhaven-abc123.png", thumb: "", resolution: "2560x1440",
          purity: "sfw", type: "image/png" },
        { id: "x9y8z7", path: "https://w.wallhaven.cc/full/x9/wallhaven-x9y8z7.jpg", thumb: "", resolution: "1920x1080",
          purity: "nsfw", type: "image/jpeg" }
    ]

    Component { id: panelComp; WallhavenPanel {} }
    Component { id: spyComp; SignalSpy {} }

    function test_search_url() {
        const f = Wallhaven.defaults();
        compare(Wallhaven.searchUrl("B", f, 1, false), "B/search?categories=111&purity=100&sorting=date_added&order=desc&page=1");
        f.query = "  city night ";
        f.general = false;
        f.sketchy = true;
        f.nsfw = true;
        f.atLeast = "2560x1440";
        f.ratio = "16x9";
        f.order = "asc";
        compare(Wallhaven.searchUrl("B", f, 3, false),
                "B/search?categories=011&purity=110&sorting=date_added&order=asc&page=3&q=city%20night&atleast=2560x1440&ratios=16x9",
                "NSFW left out without a key");
        compare(Wallhaven.searchUrl("B", f, 3, true).split("&")[1], "purity=111", "with a key");
        f.sfw = f.sketchy = f.nsfw = false;
        f.general = f.anime = f.people = false;
        compare(Wallhaven.searchUrl("B", f, 1, false).split("&").slice(0, 2).join("&"), "B/search?categories=111&purity=110",
                "nothing chosen: all, but NSFW only with a key");
        f.atLeast = "big; rm";
        verify(!Wallhaven.searchUrl("B", f, 1, false).includes("atleast"), "only WxH");
        const r = Wallhaven.defaults();
        r.sorting = "relevance";
        verify(Wallhaven.searchUrl("B", r, 1, false).endsWith("page=2"), "relevance without a query: a page later");
        r.query = "sea";
        verify(Wallhaven.searchUrl("B", r, 1, false).includes("page=1&q=sea"));
        compare(Wallhaven.searchUrl("", Wallhaven.defaults(), 1, false).split("?")[0], "https://wallhaven.cc/api/v1/search");
    }

    function test_parse() {
        const text = JSON.stringify({ data: [
            { id: "abc123", path: "https://x/a.png", file_type: "image/png", resolution: "2560x1440", purity: "sketchy",
              thumbs: { large: "L", small: "S" } },
            { id: "../evil", path: "https://x/b.png" },
            { id: "nopath" }
        ], meta: { last_page: 9 } });
        const r = Wallhaven.parse(text, Wallhaven.defaults());
        compare(r.wallpapers.length, 1, "only whole ones with a plain id");
        compare(r.wallpapers[0].thumb, "S");
        compare(r.wallpapers[0].purity, "sketchy");
        compare(r.pages, 9);
        verify(r.error === undefined);
        const rel = Wallhaven.defaults();
        rel.sorting = "relevance";
        compare(Wallhaven.parse(text, rel).pages, 8, "a page fewer when the first is skipped");
        compare(Wallhaven.parse("{\"error\":\"Unauthorized\"}").error, "Unauthorized");
        compare(Wallhaven.parse("<html>").error, "Wallhaven sent something unexpected");
        compare(Wallhaven.parse("{\"data\":[]}").pages, 1);
        compare(Wallhaven.fileName("/p/W/", r.wallpapers[0]), "/p/W/wallhaven-abc123.png");
        compare(Wallhaven.fileName("/p", { id: "q", type: "image/jpeg" }), "/p/wallhaven-q.jpg");
        const d = Wallhaven.downloadCommand("https://x/a b.png; rm", "/p/W/f.png");
        compare(d.slice(0, 2).join(" "), "sh -c");
        compare(d.slice(3).join("|"), "sh|https://x/a b.png; rm|/p/W/f.png", "the address and path as arguments");
    }

    function test_panel() {
        const p = createTemporaryObject(panelComp, root, { wallpapers: results, pages: 3, screenSize: "2560x1440" });
        waitForRendering(p);
        const chosen = createTemporaryObject(spyComp, root, { target: p, signalName: "chosen" });
        const edited = createTemporaryObject(spyComp, root, { target: p, signalName: "filtersEdited" });
        const paged = createTemporaryObject(spyComp, root, { target: p, signalName: "searchRequested" });
        const closed = createTemporaryObject(spyComp, root, { target: p, signalName: "closeRequested" });
        verify(!findChild(p, "wallhavenMessage").visible, "results, no message");
        compare(p.grid.count, 2);

        mouseClick(findChild(p, "wallhavenTile_1"));
        compare(chosen.count, 1);
        compare(chosen.signalArguments[0][0].id, "x9y8z7", "a click asks for that one");
        p.applying = "x9y8z7";
        verify(findChild(p, "wallhavenApplying_1").visible, "downloading shown on it");
        verify(!findChild(p, "wallhavenApplying_0").visible);
        mouseClick(findChild(p, "wallhavenTile_0"));
        compare(chosen.count, 1, "no other while one downloads");
        p.applying = "";

        const field = findChild(p, "wallhavenSearch");
        verify(field.activeFocus, "typing goes to the search");
        keyClick(Qt.Key_S);
        keyClick(Qt.Key_E);
        keyClick(Qt.Key_Return);
        compare(edited.count, 1);
        compare(edited.signalArguments[0][0].query, "se", "Enter searches what was typed");

        mouseClick(findChild(p, "wallhavenFilter_anime"));
        compare(edited.signalArguments[1][0].anime, false, "a chip asks to switch its filter");
        mouseClick(findChild(p, "wallhavenFilter_sketchy"));
        compare(edited.signalArguments[2][0].sketchy, true);
        verify(!findChild(p, "wallhavenFilter_nsfw").enabled, "NSFW needs an API key");
        p.hasKey = true;
        verify(findChild(p, "wallhavenFilter_nsfw").enabled);
        mouseClick(findChild(p, "wallhavenAtLeast"));
        compare(edited.signalArguments[3][0].atLeast, "2560x1440", "at least this screen");

        mouseClick(findChild(p, "wallhavenSort"));
        compare(p.menuOpen, "sort");
        const top = findChild(p, "wallhavenSort_toplist");
        verify(top);
        mouseClick(top);
        compare(edited.signalArguments[4][0].sorting, "toplist", "a sort chosen from the menu");
        compare(p.menuOpen, "");
        mouseClick(findChild(p, "wallhavenRatio"));
        tryVerify(() => findChild(p, "wallhavenRatio_16x9") !== null);
        mouseClick(findChild(p, "wallhavenRatio_16x9"));
        compare(edited.signalArguments[5][0].ratio, "16x9");
        mouseClick(findChild(p, "wallhavenRatio"));
        tryVerify(() => findChild(p, "wallhavenRatio_any") !== null);
        mouseClick(findChild(p, "wallhavenRatio_any"));
        compare(edited.signalArguments[6][0].ratio, "", "any shape");

        verify(!findChild(p, "wallhavenPrevious").enabled, "no page before the first");
        mouseClick(findChild(p, "wallhavenNext"));
        compare(paged.signalArguments[0][0], 2);
        p.page = 3;
        verify(!findChild(p, "wallhavenNext").enabled, "no page after the last");
        compare(findChild(p, "wallhavenPage").text, "Page 3 of 3");

        field.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(closed.count, 1, "Escape closes");
    }

    function test_messages() {
        const p = createTemporaryObject(panelComp, root, { loading: true });
        const m = findChild(p, "wallhavenMessage");
        compare(m.text, "Searching…");
        p.loading = false;
        compare(m.text, "No wallpapers found");
        p.error = "No connection to Wallhaven";
        compare(m.text, "No connection to Wallhaven");
        compare(m.color, Colors.error);
        verify(!findChild(p, "wallhavenAtLeast").visible, "no screen size: no such filter");
    }
}
