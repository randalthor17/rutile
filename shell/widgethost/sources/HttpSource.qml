// The http source (plan 4.2, D79): a JSON document, fetched every `every` seconds (at least 60, 900 when not
// given) and only when Settings > Widgets allows its address (Sources.allowed). Its fields are the document's.
import QtQuick
import qs.widgethost
import qs.services
import "../Sources.js" as Sources

WidgetSource {
    id: root
    readonly property string url: options.url ?? ""
    readonly property bool allowed: Sources.allowed(url, Settings.value("widgets.httpAllow") ?? [])
    property var request: null      // the fetch under way, dropped with the widget (a card in the Widgets app)

    function refresh() {
        if (!allowed) {
            value = {};
            error = url === "" ? "no url" : url + " is not allowed in Settings > Widgets";
            return;
        }
        const xhr = new XMLHttpRequest();
        request = xhr;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            root.request = null;
            try {
                const doc = JSON.parse(xhr.responseText);
                if (doc === null || typeof doc !== "object") throw new Error("not an object");
                root.value = doc;
                root.error = "";
            } catch (e) {
                root.error = "no JSON from " + root.url + " (" + xhr.status + ")";   // the last document stays
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }
    Component.onDestruction: {
        if (request) {
            request.onreadystatechange = null;
            request.abort();
        }
    }
    onUrlChanged: refresh()
    onAllowedChanged: refresh()
    Component.onCompleted: refresh()
    Timer {
        interval: Math.max(60, root.options.every ?? 900) * 1000
        repeat: true
        running: root.allowed
        onTriggered: root.refresh()
    }
}
