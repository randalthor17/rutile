// WallhavenService (D128) against a web server of the test's own (tests/qs/www/wallhaven): a search read into
// results and pages, relevance without a query a page later, the filters remembered without the query, an answer
// that is not 200, and a real download through curl that sets the wallpaper; a failed one leaves no file. The
// palette is a stand-in's, the greeter's folder the test's own.
// env RUTILE_TEST_PORT=@PORT@
// env RUTILE_WALLHAVEN_API=http://127.0.0.1:@PORT@/wallhaven
// env XDG_PICTURES_DIR=@WS@/Pictures
// env RUTILE_MATUGEN=@WS@/bin/fake-matugen
// env FAKE_MATUGEN_LOG=@WS@/palette.log
// env FAKE_MATUGEN_FIXTURE=@WS@/palette.json
// env RUTILE_PALETTE=@WS@/out/palette.json
// env RUTILE_GREETER_USER_DIR=@WS@/greeter
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    readonly property string base: "http://127.0.0.1:" + Quickshell.env("RUTILE_TEST_PORT") + "/wallhaven"
    readonly property string folder: Quickshell.env("XDG_PICTURES_DIR") + "/Wallpapers"
    property int stage: 0
    property string requests: ""
    QsTest { id: t }

    Process {
        id: server
        running: true
        command: ["python3", "-m", "http.server", Quickshell.env("RUTILE_TEST_PORT"), "--bind", "127.0.0.1",
                  "--directory", Quickshell.shellDir + "/www"]
        stderr: SplitParser { onRead: line => root.requests += line + "\n" }
    }
    Timer {
        interval: 1000
        running: true
        onTriggered: {
            root.stage = 1;
            WallhavenService.search(1);
        }
    }

    property string files: ""
    Process {
        id: lister
        command: ["sh", "-c", 'ls "$1"', "sh", root.folder]
        stdout: StdioCollector { onStreamFinished: { root.files = text.trim(); root.listed(); } }
    }
    signal listed()

    Timer {
        interval: 100
        repeat: true
        running: root.stage > 0 && root.stage < 6
        onTriggered: {
            const s = WallhavenService;
            if (root.stage === 1 && !s.loading) {
                t.compare(s.error, "", "no error");
                t.compare(s.wallpapers.map(w => w.id).join(), "abc123,x9y8z7", "the results, without the broken ones");
                t.compare(s.wallpapers[0].thumb, "full.png", "the small thumbnail");
                t.compare(s.pages, 7);
                t.compare(s.page, 1);
                t.verify(root.requests.includes("GET /wallhaven/search?categories=111&purity=100&sorting=date_added&order=desc&page=1 "),
                         "the first search's address: " + root.requests);
                s.setFilters({ sorting: "relevance", query: "" });
                t.verify(s.loading, "searching again");
                root.stage = 2;
            } else if (root.stage === 2 && !s.loading) {
                t.verify(root.requests.includes("sorting=relevance&order=desc&page=2 "), "relevance without a query: a page later");
                t.compare(s.pages, 6, "and a page fewer");
                const kept = Settings.stateValue("wallhaven.filters", {});
                t.compare(kept.sorting, "relevance", "the filters remembered");
                t.verify(!("query" in kept), "but not the query");
                s.base = root.base + "/missing";
                s.search(1);
                root.stage = 3;
            } else if (root.stage === 3 && !s.loading) {
                t.compare(s.error, "Wallhaven answered 404");
                t.compare(s.wallpapers.length, 0, "no results");
                s.base = root.base;
                t.verify(s.apply({ id: "abc123", path: root.base + "/full.png", type: "image/png" }), "a download starts");
                t.compare(s.applying, "abc123");
                t.verify(!s.apply({ id: "x9y8z7", path: root.base + "/full.png", type: "image/png" }), "one at a time");
                root.stage = 4;
            } else if (root.stage === 4 && s.applying === "") {
                t.compare(WallpaperService.path, root.folder + "/wallhaven-abc123.png", "set as the wallpaper");
                t.compare(ToastService.current?.text, "Wallpaper set from Wallhaven");
                t.verify(s.apply({ id: "gone11", path: root.base + "/gone.jpg", type: "image/jpeg" }), "a download that fails");
                root.stage = 5;
            } else if (root.stage === 5 && s.applying === "") {
                t.compare(WallpaperService.path, root.folder + "/wallhaven-abc123.png", "the wallpaper stays");
                t.verify(ToastService.queue.some(x => x.text === "Could not download the wallpaper"), "a toast says so");
                root.stage = 6;
                lister.running = true;
            }
        }
    }
    onListed: {
        t.compare(files, "wallhaven-abc123.png", "the downloaded one only; no part file left");
        t.done();
    }

    Timer {
        interval: 20000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage);
            t.done();
        }
    }
}
