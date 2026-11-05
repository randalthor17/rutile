pragma ComponentBehavior: Bound
// The calendar under the clock (D93): the month's days in six weeks from the locale's first day of the week, today in
// a primary circle, the chosen day in a tonal one, a dot under days with events; under it the chosen day's events.
// The arrows, Page Up and Page Down and the wheel change the month (choosing today in this month, else the 1st);
// the arrow keys move the chosen day and Home goes back to today. It grows in from the top left with the shared
// popup motion (D43) and closes when another window takes the keyboard, as the notification list (D41). Plain QtQuick
// on `events` (Calendar.icsEvents' data) and `now`, so it tests offscreen with fixed dates.
// With `calendars` (evolution-data-server's that take events, D101), a + beside the day's title opens a form in place
// of its events: the title, all day or from and to, and which calendar; Save asks for it (`addRequested`), and the
// owner says how it went (`addFinished`).
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
    property bool hasFolder: true           // false: no calendar address and no calendar folder, nothing to read
    property bool loading: false            // the calendars have not answered yet: neither "No events" nor "No calendars"
    property string note: ""                // under the events: an address that did not answer
    property bool hasApp: false             // GNOME Calendar is there to open (D95)
    property bool use24h: ClockText.uses24h(Qt.locale().timeFormat(Locale.ShortFormat))
    property var locale: Qt.locale()
    property date selected: Calendar.startOfDay(now)
    property date month: new Date(now.getFullYear(), now.getMonth(), 1)
    property var calendars: []              // Calendar.edsCalendars: where a new event can go
    property bool saving: false             // the owner is adding one
    property bool composing: false          // the form is open
    property string composeCalendar: ""     // its calendar's source
    property string composeError: ""

    readonly property real cell: Spacing.xxl + Spacing.sm
    readonly property int maxRows: 4
    readonly property var days: Calendar.monthDays(month, locale.firstDayOfWeek)
    readonly property var busy: Calendar.busyDays(events, days)
    // where a date is in `days` (0 to 41), or -1 when this month's page does not show it
    function dayIndex(date) {
        return days.findIndex(d => Calendar.sameDay(d, date));
    }
    readonly property var dayEvents: Calendar.dayEvents(events, selected, use24h, locale, ClockText.time)
    readonly property bool onToday: Calendar.sameDay(selected, now)
    readonly property real rowHeight: ControlSpec.listSpec.itemTwoLineContainerHeight
    // The tallest it gets (a full list of events), for the window: a fixed size, as the notification list's.
    readonly property real maxHeight: 2 * Spacing.md + header.height + weekdays.height + grid.height + dayTitle.height
                                      + maxRows * (rowHeight + ControlSpec.listSpec.segmentedGap) + 4 * column.spacing
                                      + (note !== "" ? noteText.height + column.spacing : 0)
                                      + (hasApp ? appButton.height + column.spacing : 0)

    signal settingsRequested()
    signal eventOpened(string uuid)          // an evolution-data-server event clicked: GNOME Calendar opens it (D95)
    signal appRequested()                    // "Open Calendar"
    signal windowFocusLost()
    signal addRequested(string source, bool allDay, date start, date end, string title)
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
    function compose() {
        if (calendars.length === 0) return;
        const start = Calendar.suggestedStart(selected, now);
        titleField.text = "";
        startField.text = Calendar.clockText(start, use24h);
        endField.text = Calendar.clockText(start + 60, use24h);
        allDaySwitch.checked = false;
        if (!calendars.some(c => c.source === composeCalendar)) composeCalendar = calendars[0].source;
        composeError = "";
        composing = true;
        titleField.input.forceActiveFocus();
    }
    function cancelCompose() {
        composing = false;
        root.forceActiveFocus();
    }
    function save() {
        if (saving) return;
        const title = titleField.text.trim();
        if (title === "") {
            composeError = "Give it a title";
            titleField.input.forceActiveFocus();
            return;
        }
        const times = Calendar.newEventTimes(selected, allDaySwitch.checked, startField.text, endField.text);
        if (times.error) {
            composeError = times.error;
            return;
        }
        composeError = "";
        addRequested(composeCalendar, allDaySwitch.checked, times.start, times.end, title);
    }
    // the owner's answer to addRequested: added (the form closes), or why not (it stays, to try again)
    function addFinished(ok, error) {
        if (ok) cancelCompose();
        else composeError = error || "The event could not be added";
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

    // the arrows move the day, except while the form is open (its fields' keys that they do not use come here)
    Keys.onPressed: event => {
        if (composing) {
            if (event.key === Qt.Key_Escape) cancelCompose();
            else return;
        } else if (event.key === Qt.Key_Left) moveDay(-1);
        else if (event.key === Qt.Key_Right) moveDay(1);
        else if (event.key === Qt.Key_Up) moveDay(-7);
        else if (event.key === Qt.Key_Down) moveDay(7);
        else if (event.key === Qt.Key_PageUp) moveMonth(-1);
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
    color: Panels.tint(Colors.surfaceContainer)

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
        // The 42 days as bare numbers, with one pointer area, one hover circle and the two filled circles moved to
        // their day: a circle, a dot and a StateLayer in each cell cost about 1.3 MB more while the calendar was
        // open (docs/memory.md, D31).
        Item {
            width: grid.width
            height: grid.height
            // today's circle and the chosen day's, under the numbers: two circles moved to their day, not one in each
            // of the 42 cells
            Rectangle {
                objectName: "calendarChosenCircle"
                readonly property int index: root.dayIndex(root.selected)
                visible: index >= 0 && index !== root.dayIndex(root.now)
                x: (index % 7) * root.cell + Spacing.xs / 2
                y: Math.floor(index / 7) * root.cell + Spacing.xs / 2
                width: root.cell - Spacing.xs
                height: width
                radius: width / 2
                color: Colors.secondaryContainer
            }
            Rectangle {
                objectName: "calendarTodayCircle"
                readonly property int index: root.dayIndex(root.now)
                visible: index >= 0
                x: (index % 7) * root.cell + Spacing.xs / 2
                y: Math.floor(index / 7) * root.cell + Spacing.xs / 2
                width: root.cell - Spacing.xs
                height: width
                radius: width / 2
                color: Colors.primary
            }
            Grid {
                id: grid
                columns: 7
                Repeater {
                    model: root.days
                    delegate: Text {
                        id: day
                        required property date modelData
                        readonly property bool inMonth: modelData.getMonth() === root.month.getMonth()
                        readonly property bool today: Calendar.sameDay(modelData, root.now)
                        readonly property bool chosen: Calendar.sameDay(modelData, root.selected)
                        readonly property bool busy: root.busy[Calendar.dayKey(modelData)] === true
                        objectName: "calendarDay_" + Calendar.dayKey(modelData)
                        width: root.cell
                        height: root.cell
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.getDate()
                        color: today ? Colors.primaryOn : chosen ? Colors.secondaryContainerOn
                             : inMonth ? Colors.surfaceOn : Colors.outline
                        font: Type.font(Type.bodyMedium)
                        Accessible.role: Accessible.Button
                        Accessible.name: root.locale.toString(modelData, "dddd, MMMM d") + (busy ? ", events" : "")
                    }
                }
            }
            // a dot under each day with events: only those days have one
            Repeater {
                model: root.days.map((d, i) => root.busy[Calendar.dayKey(d)] === true ? i : -1).filter(i => i >= 0)
                delegate: Rectangle {
                    required property int modelData
                    objectName: "calendarDot"
                    x: (modelData % 7 + 0.5) * root.cell - width / 2
                    y: (Math.floor(modelData / 7) + 1) * root.cell - Spacing.xs / 2 - Spacing.xs - height
                    width: Spacing.xs
                    height: width
                    radius: width / 2
                    color: Calendar.sameDay(root.days[modelData], root.now) ? Colors.primaryOn : Colors.primary
                }
            }
            MouseArea {
                id: dayPointer
                objectName: "calendarDays"
                anchors.fill: grid
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                readonly property int column: Math.floor(mouseX / root.cell)
                readonly property int row: Math.floor(mouseY / root.cell)
                // the day at a point, as an index into root.days; -1 when none
                function at(x, y) {
                    const c = Math.floor(x / root.cell), r = Math.floor(y / root.cell);
                    return c >= 0 && c < 7 && r >= 0 && 7 * r + c < root.days.length ? 7 * r + c : -1;
                }
                // the one under the pointer (the click's own point: a click may come without a hover first)
                readonly property int index: containsMouse || pressed ? at(mouseX, mouseY) : -1
                onClicked: mouse => {
                    const i = at(mouse.x, mouse.y);
                    if (i >= 0) root.select(root.days[i]);
                }
            }
            StateLayer {
                objectName: "calendarHover"
                input: dayPointer
                x: dayPointer.column * root.cell + Spacing.xs / 2
                y: dayPointer.row * root.cell + Spacing.xs / 2
                width: root.cell - Spacing.xs
                height: width
                radius: width / 2
                stateColor: dayPointer.index >= 0 && Calendar.sameDay(root.days[dayPointer.index], root.now)
                            ? Colors.primaryOn : Colors.surfaceOn
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (event.angleDelta.y !== 0) root.moveMonth(event.angleDelta.y > 0 ? -1 : 1);
                }
            }
        }

        // ---- the chosen day's events ----
        Item {
            width: parent.width
            height: dayTitle.height
            Text {
                id: dayTitle
                objectName: "calendarDayTitle"
                leftPadding: Spacing.sm
                topPadding: Spacing.xs
                text: root.locale.toString(root.selected, "dddd, MMMM d")
                color: Colors.surfaceOn
                font: Type.font(Type.titleSmall)
            }
            IconButton {
                objectName: "calendarAdd"
                visible: root.calendars.length > 0 && !root.composing
                anchors.right: parent.right
                anchors.verticalCenter: dayTitle.verticalCenter
                anchors.verticalCenterOffset: Spacing.xs / 2
                size: "xs"
                iconName: "add"
                Accessible.name: "Add an event"
                onClicked: root.compose()
            }
        }
        // ---- a new event (D101), in place of the day's events ----
        Column {
            id: composeForm
            objectName: "calendarCompose"
            visible: root.composing
            width: parent.width
            spacing: Spacing.sm
            TextField {
                id: titleField
                objectName: "calendarTitleField"
                width: parent.width
                label: "Title"
                backgroundColor: Colors.surfaceContainer
                enabled: !root.saving
                onAccepted: root.save()
            }
            Item {
                width: parent.width
                height: chooser.height
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Spacing.sm
                    Switch {
                        id: allDaySwitch
                        objectName: "calendarAllDay"
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: !root.saving
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "All day"
                        color: Colors.surfaceOn
                        font: Type.font(Type.bodyMedium)
                    }
                }
                // which calendar, when there is a choice
                Button {
                    id: chooser
                    objectName: "calendarChoose"
                    anchors.right: parent.right
                    visible: root.calendars.length > 1
                    type: "text"
                    size: "xs"
                    iconName: "calendar_month"
                    text: root.calendars.find(c => c.source === root.composeCalendar)?.name ?? ""
                    enabled: !root.saving
                    onClicked: calendarMenu.open = !calendarMenu.open
                }
            }
            Row {
                visible: !allDaySwitch.checked
                width: parent.width
                spacing: Spacing.sm
                TextField {
                    id: startField
                    objectName: "calendarStartField"
                    width: (parent.width - parent.spacing) / 2
                    label: "Starts"
                    backgroundColor: Colors.surfaceContainer
                    enabled: !root.saving
                    onAccepted: root.save()
                }
                TextField {
                    id: endField
                    objectName: "calendarEndField"
                    width: (parent.width - parent.spacing) / 2
                    label: "Ends"
                    backgroundColor: Colors.surfaceContainer
                    enabled: !root.saving
                    onAccepted: root.save()
                }
            }
            Item {
                width: parent.width
                height: saveButton.height
                Text {
                    objectName: "calendarComposeError"
                    anchors.left: parent.left
                    anchors.right: buttons.left
                    anchors.leftMargin: Spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: root.composeError
                    color: Colors.error
                    font: Type.font(Type.bodySmall)
                }
                Row {
                    id: buttons
                    anchors.right: parent.right
                    spacing: Spacing.xs
                    Button {
                        objectName: "calendarCancel"
                        type: "text"
                        size: "xs"
                        text: "Cancel"
                        onClicked: root.cancelCompose()
                    }
                    Button {
                        id: saveButton
                        objectName: "calendarSave"
                        type: "filled"
                        size: "xs"
                        text: root.saving ? "Saving…" : "Save"
                        enabled: !root.saving
                        onClicked: root.save()
                    }
                }
            }
        }
        Text {
            objectName: "calendarEmpty"
            visible: root.dayEvents.length === 0 && !root.composing && !root.loading
            leftPadding: Spacing.sm
            width: parent.width
            wrapMode: Text.Wrap
            text: root.hasFolder ? "No events" : "No calendars yet. Add your Google account in Settings > Calendar."
            color: Colors.surfaceVariantOn
            font: Type.font(Type.bodyMedium)
        }
        Button {
            objectName: "calendarSettings"
            visible: !root.hasFolder && !root.loading
            type: "text"
            size: "xs"
            text: "Calendar settings"
            onClicked: root.settingsRequested()
        }
        Flickable {
            id: flick
            visible: root.dayEvents.length > 0 && !root.composing
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
                        // GNOME Calendar edits what came from evolution-data-server; the others have nowhere to go
                        onClicked: if (modelData.uuid !== "") root.eventOpened(modelData.uuid)
                    }
                }
            }
        }
        Text {
            id: noteText
            objectName: "calendarNote"
            visible: root.note !== ""
            leftPadding: Spacing.sm
            width: parent.width
            wrapMode: Text.Wrap
            text: root.note
            color: Colors.surfaceVariantOn
            font: Type.font(Type.bodySmall)
        }
        Button {
            id: appButton
            objectName: "calendarApp"
            visible: root.hasApp
            type: "text"
            size: "xs"
            iconName: "edit_calendar"
            text: "Open Calendar"
            onClicked: root.appRequested()
        }
    }

    PopupLoader {
        id: calendarMenu
        origin: Item.Top
        x: column.x + composeForm.x + composeForm.width - ((item as Item)?.width ?? 0)
        y: column.y + composeForm.y + chooser.parent.y + chooser.height
        sourceComponent: Menu {
            itemPrefix: "calendarChoice_"
            items: root.calendars.map(c => ({ id: c.source, text: c.name, icon: "calendar_month", check: "radio",
                                              checked: c.source === root.composeCalendar }))
            onChosen: id => {
                calendarMenu.open = false;
                root.composeCalendar = id;
            }
        }
    }
}
