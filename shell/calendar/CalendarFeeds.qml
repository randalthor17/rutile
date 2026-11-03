// The calendar addresses' events (D94): each address in `addresses` (Google Calendar's "Secret address in iCal
// format", or any other calendar's .ics address) is fetched once when this is created, as the calendar opens, and
// `refresh()` fetches again. What an address last answered is kept in `cacheDir` (one file per address, named by a
// hash of it), so the events show at once, and offline. `text` is every address's calendar text, one after the other;
// `failed` the addresses that did not answer with a calendar this time (their saved events stay).
import QtQuick
import Quickshell
import Quickshell.Io
import "Calendar.js" as Calendar

Scope {
    id: root

    property var addresses: []
    property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/rutile/calendars"
    property int revision: 0                // one of the feeds' texts or states changed
    readonly property string text: {
        revision;
        let t = "";
        for (let i = 0; i < feeds.count; i++) t += (feeds.objectAt(i)?.text ?? "") + "\n";
        return t;
    }
    readonly property var failed: {
        revision;
        const out = [];
        for (let i = 0; i < feeds.count; i++) if (feeds.objectAt(i)?.failed) out.push(feeds.objectAt(i).address);
        return out;
    }
    readonly property bool busy: {
        revision;
        for (let i = 0; i < feeds.count; i++) if (feeds.objectAt(i)?.request) return true;
        return false;
    }

    function refresh() {
        for (let i = 0; i < feeds.count; i++) feeds.objectAt(i)?.fetch();
    }

    // the cache folder, before a feed writes to it
    Process {
        running: true
        command: ["mkdir", "-p", root.cacheDir]
    }

    Instantiator {
        id: feeds
        model: (root.addresses ?? []).filter(a => Calendar.feedUrl(a) !== "")
        onObjectAdded: root.revision++
        onObjectRemoved: root.revision++
        delegate: Scope {
            id: feed
            required property string modelData
            readonly property string address: modelData
            property string text: ""
            property bool failed: false
            property var request: null
            onTextChanged: root.revision++
            onFailedChanged: root.revision++
            onRequestChanged: root.revision++

            function fetch() {
                if (request) return;
                const xhr = new XMLHttpRequest();
                request = xhr;
                xhr.onreadystatechange = () => {
                    if (xhr.readyState !== XMLHttpRequest.DONE) return;
                    feed.request = null;
                    const t = xhr.responseText;
                    if (xhr.status === 200 && Calendar.isCalendar(t)) {
                        feed.failed = false;
                        if (t !== feed.text) {
                            feed.text = t;
                            cache.setText(t);
                        }
                    } else {
                        feed.failed = true;
                    }
                };
                xhr.open("GET", Calendar.feedUrl(address));
                xhr.send();
            }
            Component.onCompleted: fetch()
            Component.onDestruction: {
                if (request) {
                    request.onreadystatechange = null;
                    request.abort();
                }
            }

            // what it last answered; a fetch that comes first wins
            FileView {
                id: cache
                path: root.cacheDir + "/" + Calendar.cacheName(feed.address) + ".ics"
                atomicWrites: true
                printErrors: false
                onLoaded: if (feed.text === "" && Calendar.isCalendar(cache.text())) feed.text = cache.text()
            }
        }
    }
}
