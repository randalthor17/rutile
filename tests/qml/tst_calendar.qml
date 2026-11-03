import QtQuick
import QtTest
import qs.common
import qs.calendar
import qs.bar
import "../qs/calendar/Calendar.js" as Calendar
import "../qs/bar/ClockText.js" as ClockText

TestCase {
    id: root
    name: "Calendar"
    width: 500
    height: 800
    visible: true
    when: windowShown

    readonly property var en: Qt.locale("en_US")

    function ics(...events) {
        return "BEGIN:VCALENDAR\r\n" + events.map(e => "BEGIN:VEVENT\r\n" + e.join("\r\n") + "\r\nEND:VEVENT\r\n").join("")
               + "END:VCALENDAR\r\n";
    }
    function day(y, m, d) { return new Date(y, m - 1, d); }
    // the days (YYYY-MM-DD) an event's times start on between two days
    function starts(text, from, to) {
        return Calendar.occurrences(Calendar.icsEvents(text), from, to).map(o => Calendar.dayKey(o.start)).join(",");
    }

    // ---- reading ----
    function test_single_events() {
        const e = Calendar.icsEvents(ics(["SUMMARY:Dentist\\, Dr. A", "DTSTART:20261105T090000Z", "DTEND:20261105T100000Z"],
                                         ["DTSTART;VALUE=DATE:20261103", "SUMMARY:Holi", " day"],
                                         ["SUMMARY:Call", "DTSTART:20261106T150000", "DURATION:PT45M"],
                                         ["SUMMARY:Pin", "DTSTART:20261107T080000"]));
        compare(e.length, 4);
        compare(e[0].title, "Dentist, Dr. A");
        compare(e[0].end - e[0].start, 3600000, "DTEND");
        compare(e[1].title, "Holiday", "folded lines joined");
        verify(e[1].allDay);
        compare(e[1].end - e[1].start, 86400000, "an all-day event without an end is one day");
        compare(e[2].end - e[2].start, 45 * 60000, "DURATION");
        compare(e[3].end - e[3].start, 0, "no end, no duration");
        compare(e[0].rule, null);
        compare(Calendar.icsDuration("P1DT2H"), (26 * 60) * 60000);
        compare(Calendar.icsDuration("-PT15M"), -15 * 60000);
        compare(Calendar.icsDuration("nonsense"), 0);
    }

    // ---- repeating ----
    function test_daily_interval_count() {
        compare(starts(ics(["SUMMARY:A", "DTSTART:20261101T090000", "RRULE:FREQ=DAILY;INTERVAL=2;COUNT=3"]),
                       day(2026, 10, 1), day(2026, 12, 1)), "2026-11-01,2026-11-03,2026-11-05");
        compare(starts(ics(["SUMMARY:A", "DTSTART:20261101T090000", "RRULE:FREQ=DAILY;COUNT=10"]),
                       day(2026, 11, 8), day(2026, 12, 1)), "2026-11-08,2026-11-09,2026-11-10",
                "COUNT counts from the start, not from the range");
        compare(starts(ics(["SUMMARY:A", "DTSTART:20261101T090000", "RRULE:FREQ=DAILY;UNTIL=20261103T090000"]),
                       day(2026, 10, 1), day(2026, 12, 1)), "2026-11-01,2026-11-02,2026-11-03", "UNTIL a time is inclusive");
        compare(starts(ics(["SUMMARY:A", "DTSTART;VALUE=DATE:20261101", "RRULE:FREQ=DAILY;UNTIL=20261103"]),
                       day(2026, 10, 1), day(2026, 12, 1)), "2026-11-01,2026-11-02,2026-11-03", "UNTIL a date is inclusive");
    }
    function test_far_from_start() {
        // a daily event begun 30 years ago still shows today, without walking every day since
        compare(starts(ics(["SUMMARY:Old", "DTSTART:19961104T080000", "RRULE:FREQ=DAILY"]),
                       day(2026, 11, 4), day(2026, 11, 6)), "2026-11-04,2026-11-05");
        compare(starts(ics(["SUMMARY:Old", "DTSTART:19961104T080000", "RRULE:FREQ=MONTHLY"]),
                       day(2026, 11, 1), day(2027, 1, 1)), "2026-11-04,2026-12-04");
    }
    function test_weekly_byday_exdate() {
        // Mon and Wed from Wed Nov 4 2026; Nov 9 left out
        const text = ics(["SUMMARY:Gym", "UID:g", "DTSTART:20261104T180000", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE",
                          "EXDATE:20261109T180000"]);
        compare(starts(text, day(2026, 11, 1), day(2026, 11, 19)), "2026-11-04,2026-11-11,2026-11-16,2026-11-18",
                "not before the start; the EXDATE left out");
        compare(starts(ics(["SUMMARY:B", "DTSTART:20261104T180000", "RRULE:FREQ=WEEKLY;INTERVAL=2"]),
                       day(2026, 11, 1), day(2026, 12, 3)), "2026-11-04,2026-11-18,2026-12-02");
    }
    function test_recurrence_id_replaces() {
        const text = ics(["SUMMARY:Standup", "UID:s", "DTSTART:20261102T100000", "RRULE:FREQ=DAILY;COUNT=3"],
                         ["SUMMARY:Standup (moved)", "UID:s", "RECURRENCE-ID:20261103T100000", "DTSTART:20261103T140000"]);
        const o = Calendar.occurrences(Calendar.icsEvents(text), day(2026, 11, 1), day(2026, 11, 10));
        compare(o.map(x => x.title + "@" + x.start.getDate() + ":" + x.start.getHours()).join(","),
                "Standup@2:10,Standup (moved)@3:14,Standup@4:10");
    }
    function test_monthly_and_yearly() {
        compare(starts(ics(["SUMMARY:Rent", "DTSTART:20261031T090000", "RRULE:FREQ=MONTHLY"]),
                       day(2026, 10, 1), day(2027, 2, 1)), "2026-10-31,2026-12-31,2027-01-31",
                "a month without the 31st has none (RFC 5545)");
        compare(starts(ics(["SUMMARY:Meetup", "DTSTART:20261109T190000", "RRULE:FREQ=MONTHLY;BYDAY=2MO"]),
                       day(2026, 11, 1), day(2027, 2, 1)), "2026-11-09,2026-12-14,2027-01-11", "the second Monday");
        compare(starts(ics(["SUMMARY:Pay", "DTSTART:20261127T090000", "RRULE:FREQ=MONTHLY;BYDAY=-1FR"]),
                       day(2026, 11, 1), day(2027, 1, 1)), "2026-11-27,2026-12-25", "the last Friday");
        compare(starts(ics(["SUMMARY:End", "DTSTART:20261130T090000", "RRULE:FREQ=MONTHLY;BYMONTHDAY=-1"]),
                       day(2026, 11, 1), day(2027, 3, 1)), "2026-11-30,2026-12-31,2027-01-31,2027-02-28", "the last day");
        compare(starts(ics(["SUMMARY:Birthday", "DTSTART;VALUE=DATE:20000229", "RRULE:FREQ=YEARLY"]),
                       day(2026, 1, 1), day(2029, 1, 1)), "2028-02-29", "Feb 29 only in leap years");
    }
    function test_unsupported_rule_shows_first_time() {
        compare(starts(ics(["SUMMARY:X", "DTSTART:20261104T090000", "RRULE:FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1"]),
                       day(2026, 11, 1), day(2027, 3, 1)), "2026-11-04");
        compare(starts(ics(["SUMMARY:X", "DTSTART:20261104T090000", "RRULE:FREQ=HOURLY"]),
                       day(2026, 11, 1), day(2027, 3, 1)), "2026-11-04");
    }
    function test_overlap() {
        // a three-day all-day event is on each of its days, not the day it ends
        const text = ics(["SUMMARY:Trip", "DTSTART;VALUE=DATE:20261102", "DTEND;VALUE=DATE:20261105"]);
        const e = Calendar.icsEvents(text);
        compare(Calendar.occurrences(e, day(2026, 11, 4), day(2026, 11, 5)).length, 1, "on its last day");
        compare(Calendar.occurrences(e, day(2026, 11, 5), day(2026, 11, 6)).length, 0, "not on its end");
        compare(Object.keys(Calendar.busyDays(e, Calendar.monthDays(day(2026, 11, 1), 0))).sort().join(),
                "2026-11-02,2026-11-03,2026-11-04");
    }

    // ---- the month ----
    function test_month_days() {
        // Nov 1 2026 is a Sunday
        const sun = Calendar.monthDays(day(2026, 11, 15), 0);
        compare(sun.length, 42);
        compare(Calendar.dayKey(sun[0]), "2026-11-01");
        const mon = Calendar.monthDays(day(2026, 11, 15), 1);
        compare(Calendar.dayKey(mon[0]), "2026-10-26", "a Monday week starts in October");
        compare(Calendar.dayKey(mon[41]), "2026-12-06");
        compare(Calendar.dayKey(Calendar.monthDays(day(2026, 11, 1), 7)[0]), "2026-11-01", "Qt's 7 is Sunday too");
        compare(Calendar.parseDay("2026-02-30"), null);
        compare(Calendar.dayKey(Calendar.parseDay("2026-02-28")), "2026-02-28");
        compare(Calendar.expandHome("~/.calendars", "/home/a"), "/home/a/.calendars");
        compare(Calendar.expandHome("/srv/cal", "/home/a"), "/srv/cal");
    }
    function test_day_events() {
        const e = Calendar.icsEvents(ics(["SUMMARY:Late", "DTSTART:20261104T230000", "DTEND:20261105T010000"],
                                         ["SUMMARY:Holiday", "DTSTART;VALUE=DATE:20261104"],
                                         ["SUMMARY:Pin", "DTSTART:20261104T080000"]));
        compare(JSON.stringify(Calendar.dayEvents(e, day(2026, 11, 4), true, en, ClockText.time)),
                JSON.stringify([{ title: "Holiday", time: "All day" }, { title: "Pin", time: "08:00" },
                                { title: "Late", time: "23:00 – Nov 5, 01:00" }]));
        compare(Calendar.dayEvents(e, day(2026, 11, 5), false, en, ClockText.time)[0].time, "Nov 4, 11:00 – 1:00",
                "the next day shows when it began");
    }

    // ---- the panel ----
    Component { id: panelComp; CalendarPanel {} }
    function panel(props) {
        const p = createTemporaryObject(panelComp, root, Object.assign({ now: new Date(2026, 10, 4, 9, 30), locale: en,
                                                                         use24h: true }, props || {}));
        tryCompare(p, "opacity", 1);
        return p;
    }
    readonly property string sample: ics(["SUMMARY:Gym", "DTSTART:20261104T180000", "DTEND:20261104T190000",
                                          "RRULE:FREQ=WEEKLY"],
                                         ["SUMMARY:Holiday", "DTSTART;VALUE=DATE:20261104"])

    function test_panel_today() {
        const p = panel({ events: Calendar.icsEvents(sample) });
        compare(findChild(p, "calendarMonth").text, "November 2026");
        compare(findChild(p, "calendarDayTitle").text, "Wednesday, November 4");
        compare(p.dayEvents.map(e => e.title + " " + e.time).join("|"), "Holiday All day|Gym 18:00 – 19:00");
        compare(findChild(p, "calendarEvent_1").text, "Gym");
        compare(findChild(p, "calendarEvent_1").supportingText, "18:00 – 19:00");
        verify(!findChild(p, "calendarToday").visible, "already on today");
        verify(findChild(p, "calendarDay_2026-11-11").busy, "the weekly event marks the next week");
        verify(!findChild(p, "calendarDay_2026-11-12").busy);
        verify(findChild(p, "calendarDay_2026-11-04").today);
        verify(!findChild(p, "calendarEmpty").visible);
    }
    function test_panel_click_day_and_months() {
        const p = panel({ events: Calendar.icsEvents(sample) });
        mouseClick(findChild(p, "calendarDay_2026-11-12"));
        compare(Calendar.dayKey(p.selected), "2026-11-12");
        verify(findChild(p, "calendarDay_2026-11-12").chosen);
        verify(findChild(p, "calendarEmpty").visible);
        compare(findChild(p, "calendarEmpty").text, "No events");
        verify(findChild(p, "calendarToday").visible);
        waitForItemPolished(findChild(p, "calendarToday").parent);     // the row has made room for it
        mouseClick(findChild(p, "calendarToday"));
        compare(Calendar.dayKey(p.selected), "2026-11-04");
        mouseClick(findChild(p, "calendarNext"));
        compare(findChild(p, "calendarMonth").text, "December 2026");
        compare(Calendar.dayKey(p.selected), "2026-12-01", "another month: its 1st");
        mouseClick(findChild(p, "calendarPrevious"));
        compare(Calendar.dayKey(p.selected), "2026-11-04", "back to this month: today");
        // a day of the next month shown in this one's last week moves to that month
        mouseClick(findChild(p, "calendarDay_2026-12-02"));
        compare(findChild(p, "calendarMonth").text, "December 2026");
    }
    function test_panel_keys() {
        const p = panel();
        p.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(Calendar.dayKey(p.selected), "2026-11-05");
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Left);
        compare(Calendar.dayKey(p.selected), "2026-11-03");
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Down);
        compare(Calendar.dayKey(p.selected), "2026-11-12");
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Up);
        compare(Calendar.dayKey(p.selected), "2026-10-29");
        compare(findChild(p, "calendarMonth").text, "October 2026", "the month follows the day");
        keyClick(Qt.Key_Home);
        compare(Calendar.dayKey(p.selected), "2026-11-04");
        keyClick(Qt.Key_PageDown);
        compare(findChild(p, "calendarMonth").text, "December 2026");
        keyClick(Qt.Key_PageUp);
        keyClick(Qt.Key_PageUp);
        compare(findChild(p, "calendarMonth").text, "October 2026");
    }
    function test_panel_wheel() {
        const p = panel();
        let d = findChild(p, "calendarDay_2026-11-12");
        mouseWheel(d, d.width / 2, d.height / 2, 0, -120);
        compare(findChild(p, "calendarMonth").text, "December 2026");
        d = findChild(p, "calendarDay_2026-12-10");     // the month's days are new ones
        mouseWheel(d, d.width / 2, d.height / 2, 0, 120);
        compare(findChild(p, "calendarMonth").text, "November 2026");
    }
    function test_panel_week_start() {
        const p = panel({ locale: Qt.locale("de_DE") });
        verify(findChild(p, "calendarDay_2026-10-26"), "a German week starts on Monday");
        const s = panel({ locale: en });
        verify(!findChild(s, "calendarDay_2026-10-26"), "an American one on Sunday");
    }
    function test_panel_no_folder() {
        const p = panel({ hasFolder: false });
        verify(findChild(p, "calendarEmpty").text.startsWith("No calendar folder"));
        const button = findChild(p, "calendarSettings");
        verify(button.visible);
        const spy = createTemporaryObject(spyComp, root, { target: p, signalName: "settingsRequested" });
        mouseClick(button);
        compare(spy.count, 1);
    }
    function test_panel_fixed_height() {
        // the window keeps the tallest the panel gets: a day with many events stays within it
        const many = [];
        for (let i = 0; i < 9; i++) many.push(["SUMMARY:E" + i, "DTSTART:20261104T1" + i + "0000"]);
        const p = panel({ events: Calendar.icsEvents(ics(...many)) });
        compare(p.dayEvents.length, 9);
        verify(p.height <= p.maxHeight + 0.5, p.height + " within " + p.maxHeight);
        verify(p.height > p.maxHeight - 1, "a full list is the tallest");
    }
    Component { id: spyComp; SignalSpy {} }

    // ---- the clock's open look ----
    Component { id: pillComp; ClockPill {} }
    function test_clock_open() {
        const pill = createTemporaryObject(pillComp, root, { now: new Date(2026, 10, 4, 9, 30) });
        compare(pill.color, Colors.surfaceContainer);
        pill.open = true;
        tryCompare(pill, "color", Colors.secondaryContainer);
    }
}
