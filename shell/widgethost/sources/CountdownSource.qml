// The countdown source (plan 4.2, D79): Sources.countdown at every minute.
import QtQuick
import qs.widgethost
import "../Sources.js" as Sources

WidgetSource {
    id: root

    function update() {
        const now = new Date();
        value = Sources.countdown(now, options);
        tick.interval = 60000 - now.getSeconds() * 1000 - now.getMilliseconds();
        tick.restart();
    }
    onOptionsChanged: update()
    Component.onCompleted: update()
    Timer {
        id: tick
        onTriggered: root.update()
    }
}
