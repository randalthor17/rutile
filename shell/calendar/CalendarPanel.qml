pragma ComponentBehavior: Bound
// The calendar under the clock (D93): the month's days in six weeks from the locale's first day of the week, today in
// a primary circle, the chosen day in a tonal one, a dot under days with events; under it the chosen day's events.
// The arrows, Page Up and Page Down and the wheel change the month (choosing today in this month, else the 1st);
// the arrow keys move the chosen day and Home goes back to today. It grows in from the top left with the shared
// popup motion (D43) and closes when another window takes the keyboard, as the notification list (D41). Plain QtQuick
// on `events` (Calendar.icsEvents' data) and `now`, so it tests offscreen with fixed dates.
import QtQuick
import qs.common
import qs.components
import "Calendar.js" as Calendar
import "../bar/ClockText.js" as ClockText

Rectangle {
    id: root

    property var events: []
    property date now: new Date()
    property bool shown: true
    property bool hasFolder: true           // false: the calendar folder is missing, nothing to read
    property bool use24h: ClockText.uses24h(Qt.locale().timeFormat(Locale.ShortFormat))
    property var locale: Qt.locale()
    property date selected: Calendar.startOfDay(now)
    property date month: new Date(now.getFullYear(), now.getMonth(), 1)

    readonly property real cell: Spacing.xxl + Spacing.sm
    readonly property int maxRows: 4
    readonly property var days: Calendar.monthDays(month, locale.firstDayOfWeek)
    readonly property var busy: Calendar.busyDays(events, days)
    readonly property var dayEvents: Calendar.dayEvents(events, selected, use24h, locale, ClockText.time)
    readonly property bool onToday: Calendar.sameDay(selected, now)
    readonly property real rowHeight: ControlSpec.listSpec.itemTwoLineContainerHeight
    // The tallest it gets (a full list of events), for the window: a fixed size, as the notification list's.
    readonly property real maxHeight: 2 * Spacing.md + header.height + weekdays.height + grid.height + dayTitle.height
                                      + maxRows * (rowHeight + ControlSpec.listSpec.segmentedGap) + 4 * column.spacing

    signal settingsRequested()
    signal windowFocusLost()
    signal hidden()

    function select(day) {
        selected = Calendar.startOfDay(day);
        if (day.getMonth() !== month.getMonth() || day.getFullYear() !== month.getFullYear())
            month = new Date(day.getFullYear(), day.getMonth(), 1);
    }
    function moveMonth(step) {
        const m = new Date(month.getFullYear(), month.getMonth() + step, 1);
        month = m;
        selected = m.getMonth() === now.getMonth() && m.getFullYear() === now.getFullYear() ? Calendar.startOfDay(now) : m;
    }
    function moveDay(step) {
        select(new Date(selected.getFullYear(), selected.getMonth(), selected.getDate() + step));
    }

    property bool windowActive: Window.active   // not readonly: the offscreen tests cannot move window focus
    property bool hadWindowFocus: false
    onWindowActiveChanged: {
        if (windowActive) hadWindowFocus = true;
        else if (hadWindowFocus) windowFocusLost();
    }

    Keys.onLeftPressed: moveDay(-1)
    Keys.onRightPressed: moveDay(1)
    Keys.onUpPressed: moveDay(-7)
    Keys.onDownPressed: moveDay(7)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp) moveMonth(-1);
        else if (event.key === Qt.Key_PageDown) moveMonth(1);
        else if (event.key === Qt.Key_Home) select(now);
        else return;
        event.accepted = true;
    }

    implicitWidth: 7 * cell + 2 * Spacing.md
    implicitHeight: column.height + 2 * Spacing.md
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.extraLarge
    color: Colors.surfaceContainer

    PopupMotion {
        target: root
        shown: root.shown
        origin: Item.TopLeft
        onHidden: root.hidden()
    }

    Column {
        id: column
        x: Spacing.md
        y: Spacing.md
        width: root.width - 2 * Spacing.md
        spacing: Spacing.sm

        // ---- the month, today, back and forth ----
        Item {
            id: header
            width: parent.width
            height: ControlSpec.iconButtonSizes.s.height
            Text {
                objectName: "calendarMonth"
                anchors.left: parent.left
                anchors.leftMargin: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: root.locale.toString(root.month, "MMMM yyyy")
                color: Colors.surfaceOn
                font: Type.font(Type.titleMedium)
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                IconButton {
                    objectName: "calendarToday"
                    visible: !root.onToday
                    iconName: "today"
                    Accessible.name: "Today"
                    onClicked: root.select(root.now)
                }
                IconButton {
                    objectName: "calendarPrevious"
                    iconName: "chevron_left"
                    Accessible.name: "Previous month"
                    onClicked: root.moveMonth(-1)
                }
                IconButton {
                    objectName: "calendarNext"
                    iconName: "chevron_right"
                    Accessible.name: "Next month"
                    onClicked: root.moveMonth(1)
                }
            }
        }

        // ---- the days of the week, then the days ----
        Row {
            id: weekdays
            Repeater {
                model: 7
                delegate: Text {
                    required property int index
                    width: root.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: root.locale.dayName((root.locale.firstDayOfWeek + index) % 7, Locale.NarrowFormat)
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.labelMedium)
                }
            }
        }
        Grid {
            id: grid
            columns: 7
            Repeater {
                model: root.days
                delegate: Item {
                    id: day
                    required property date modelData
                    readonly property bool inMonth: modelData.getMonth() === root.month.getMonth()
                    readonly property bool today: Calendar.sameDay(modelData, root.now)
                    readonly property bool chosen: Calendar.sameDay(modelData, root.selected)
                    readonly property bool busy: root.busy[Calendar.dayKey(modelData)] === true
                    objectName: "calendarDay_" + Calendar.dayKey(modelData)
                    width: root.cell
                    height: root.cell
                    Accessible.role: Accessible.Button
                    Accessible.name: root.locale.toString(modelData, "dddd, MMMM d") + (busy ? ", events" : "")

                    Rectangle {
                        id: circle
                        anchors.centerIn: parent
                        width: root.cell - Spacing.xs
                        height: width
                        radius: width / 2
                        color: day.today ? Colors.primary : day.chosen ? Colors.secondaryContainer : "transparent"
                        Behavior on color { EffectsColor {} }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: day.modelData.getDate()
                        color: day.today ? Colors.primaryOn : day.chosen ? Colors.secondaryContainerOn
                             : day.inMonth ? Colors.surfaceOn : Colors.outline
                        font: Type.font(Type.bodyMedium)
                    }
                    Rectangle {
                        objectName: "calendarDot"
                        visible: day.busy
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: circle.bottom
                        anchors.bottomMargin: Spacing.xs
                        width: Spacing.xs
                        height: width
                        radius: width / 2
                        color: day.today ? Colors.primaryOn : Colors.primary
                    }
                    StateLayer {
                        anchors.fill: circle
                        radius: circle.radius
                        stateColor: day.today ? Colors.primaryOn : Colors.surfaceOn
                        onClicked: root.select(day.modelData)
                    }
                }
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (event.angleDelta.y !== 0) root.moveMonth(event.angleDelta.y > 0 ? -1 : 1);
                }
            }
        }

        // ---- the chosen day's events ----
        Text {
            id: dayTitle
            objectName: "calendarDayTitle"
            leftPadding: Spacing.sm
            topPadding: Spacing.xs
            text: root.locale.toString(root.selected, "dddd, MMMM d")
            color: Colors.surfaceOn
            font: Type.font(Type.titleSmall)
        }
        Text {
            objectName: "calendarEmpty"
            visible: root.dayEvents.length === 0
            leftPadding: Spacing.sm
            width: parent.width
            wrapMode: Text.Wrap
            text: root.hasFolder ? "No events" : "No calendar folder. Choose one in Settings, or sync one with vdirsyncer."
            color: Colors.surfaceVariantOn
            font: Type.font(Type.bodyMedium)
        }
        Button {
            objectName: "calendarSettings"
            visible: !root.hasFolder
            type: "text"
            size: "xs"
            text: "Calendar settings"
            onClicked: root.settingsRequested()
        }
        Flickable {
            id: flick
            visible: root.dayEvents.length > 0
            width: parent.width
            height: Math.min(list.implicitHeight, root.maxRows * (root.rowHeight + ControlSpec.listSpec.segmentedGap))
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: list
                width: flick.width
                spacing: ControlSpec.listSpec.segmentedGap
                Repeater {
                    model: root.dayEvents
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        objectName: "calendarEvent_" + index
                        width: list.width
                        position: root.dayEvents.length === 1 ? "single" : index === 0 ? "first"
                                : index === root.dayEvents.length - 1 ? "last" : "middle"
                        tone: Colors.surfaceContainerHigh
                        iconName: "event"
                        text: modelData.title
                        supportingText: modelData.time
                    }
                }
            }
        }
    }
}
