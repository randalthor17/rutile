// The calendar addresses (D94): a calendar fetched from a web server of the test's own and saved in the cache; an
// address that answers with something else (JSON) or not at all (404) failed; with the server gone, a new
// CalendarFeeds shows the saved calendar at once and marks the address failed.
// env RUTILE_TEST_PORT=@PORT@
import QtQuick
import Quickshell
import Quickshell.Io
import qs.calendar

ShellRoot {
    id: root
    readonly property string base: "http://127.0.0.1:" + Quickshell.env("RUTILE_TEST_PORT") + "/"
    readonly property string cacheDir: Quickshell.env("XDG_CACHE_HOME") + "/rutile/calendars"
    property int stage: 0
    QsTest { id: t }

    Process {
        id: server
        running: true
        command: ["python3", "-m", "http.server", Quickshell.env("RUTILE_TEST_PORT"), "--bind", "127.0.0.1",
                  "--directory", Quickshell.shellDir + "/www"]
    }

    Loader {
        id: first
        active: root.stage >= 1 && root.stage < 3
        sourceComponent: CalendarFeeds {
            cacheDir: root.cacheDir
            addresses: [root.base + "cal.ics", root.base + "rates.json", root.base + "missing.ics", "ftp://nope", ""]
        }
    }
    Loader {
        id: again
        active: root.stage >= 4
        sourceComponent: CalendarFeeds {
            cacheDir: root.cacheDir
            addresses: [root.base + "cal.ics"]
        }
    }
    Process {
        id: listCache
        command: ["sh", "-c", 'cat "$1"/*.ics; ls "$1"', "sh", root.cacheDir]
        stdout: StdioCollector { id: cacheOut }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (ticks > 150) {
                t.verify(false, "timed out at stage " + root.stage);
                t.done();
                running = false;
                return;
            }
            const f = first.item;
            if (root.stage === 0 && ticks > 10) root.stage = 1;          // the server has started
            else if (root.stage === 1 && f && !f.busy && f.failed.length === 2) {
                t.verify(f.text.includes("SUMMARY:From the web"), "the calendar fetched: " + f.text);
                t.verify(!f.text.includes("rates"), "the JSON is not a calendar");
                t.compare(f.failed.join(" "), root.base + "rates.json " + root.base + "missing.ics", "failed");
                root.stage = 2;
                listCache.running = true;
            } else if (root.stage === 2 && !listCache.running && cacheOut.text !== "") {
                t.verify(cacheOut.text.includes("SUMMARY:From the web"), "saved: " + cacheOut.text);
                t.verify(!cacheOut.text.includes("cal.ics"), "the address is in no file name");
                t.verify(/^[0-9a-f]{16}\.ics$/m.test(cacheOut.text), "a hash as the name: " + cacheOut.text);
                server.running = false;
                root.stage = 3;
            } else if (root.stage === 3 && !server.running) {
                root.stage = 4;
            } else if (root.stage === 4 && again.item && !again.item.busy && again.item.failed.length === 1) {
                t.verify(again.item.text.includes("SUMMARY:From the web"), "offline: the saved calendar");
                t.done();
                running = false;
            }
        }
    }
}
