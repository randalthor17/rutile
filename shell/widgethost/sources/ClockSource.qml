// The clock source (plan 4.2, D79): Sources.clock at every minute, or every second while `seconds` is bound.
// Each source has `options` (the widget's sources.<name>), `fields` (the ones bound) and `value`.
import QtQuick
import qs.widgethost
import "../Sources.js" as Sources
import "../../bar/ClockText.js" as ClockText

WidgetSource {
    id: root
    readonly property bool everySecond: fields.indexOf("seconds") >= 0
    readonly property bool use24h: ClockText.uses24h(Qt.locale().timeFormat(Locale.ShortFormat))

    function update() {
        const now = new Date();
        value = Sources.clock(now, options, use24h, Qt.locale());
        // the next tick at the next whole second or minute
        tick.interval = everySecond ? 1000 - now.getMilliseconds() : 60000 - now.getSeconds() * 1000 - now.getMilliseconds();
        tick.restart();
    }
    onOptionsChanged: update()
    onEverySecondChanged: update()
    Component.onCompleted: update()
    Timer {
        id: tick
        onTriggered: root.update()
    }
}
