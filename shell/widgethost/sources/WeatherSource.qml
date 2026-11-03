// The weather source (plan 4.2, D79): Open-Meteo (no key) every 30 minutes, for the widget's place or the one in
// Settings > Widgets; nothing is fetched without a place. RUTILE_WEATHER_URL replaces the address (tests).
import QtQuick
import qs.widgethost
import Quickshell
import qs.services
import "../Sources.js" as Sources

WidgetSource {
    id: root
    property string baseUrl: Quickshell.env("RUTILE_WEATHER_URL") || Sources.WEATHER_URL
    readonly property var place: Sources.weatherPlace(options, {
        latitude: Settings.value("widgets.latitude"), longitude: Settings.value("widgets.longitude"),
        units: Settings.value("widgets.units")
    })
    readonly property string url: place ? Sources.weatherUrl(place, baseUrl) : ""

    function refresh() {
        if (url === "") {
            value = {};
            error = "no place: set one in Settings > Widgets";
            return;
        }
        const units = place.units;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            let doc = null;
            try {
                doc = JSON.parse(xhr.responseText);
            } catch (e) {
                doc = null;
            }
            const v = Sources.weather(doc, units);
            error = Object.keys(v).length ? "" : "no weather from " + baseUrl + " (" + xhr.status + ")";
            if (error === "") value = v;        // a failed fetch keeps the last weather
        };
        xhr.open("GET", url);
        xhr.send();
    }
    onUrlChanged: refresh()
    Component.onCompleted: refresh()
    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: root.url !== ""
        onTriggered: root.refresh()
    }
}
