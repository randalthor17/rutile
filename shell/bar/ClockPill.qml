// The clock at the top left (Googlebook): the time and date, e.g. "8:55  Fri, Oct 9", on the same tonal container
// as the status pill so it reads on any wallpaper. Plain QtQuick: `now` comes from the window's SystemClock, so it
// tests offscreen with a fixed date. `open` marks it while the calendar it opens is showing (D93).
import QtQuick
import qs.common
import "ClockText.js" as ClockText

Rectangle {
    id: root

    required property date now
    property bool open: false
    property bool use24h: ClockText.uses24h(Qt.locale().timeFormat(Locale.ShortFormat))

    readonly property string timeText: ClockText.time(now, use24h)
    readonly property string dateText: ClockText.date(now, Qt.locale())

    implicitWidth: label.implicitWidth + 2 * Spacing.md
    implicitHeight: Spacing.xl
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: Panels.tint(open ? Colors.secondaryContainer : Colors.surfaceContainer)
    Behavior on color { EffectsColor {} }

    // One Text for both parts (D31); the em space keeps them apart as Googlebook does.
    Text {
        id: label
        objectName: "clockText"
        anchors.centerIn: parent
        text: root.timeText + " " + root.dateText
        color: root.open ? Colors.secondaryContainerOn : Colors.surfaceOn
        font: Type.font(Type.labelLarge)
    }
}
