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

    // ---- time zones (VTIMEZONE) ----
    // New York as tzurl.org writes it: the rules before 2007 (until then) and since
    readonly property string newYork: ["BEGIN:VTIMEZONE", "TZID:America/New_York",
        "BEGIN:DAYLIGHT", "TZOFFSETFROM:-0500", "TZOFFSETTO:-0400", "DTSTART:19870405T020000",
        "RRULE:FREQ=YEARLY;BYMONTH=4;BYDAY=1SU;UNTIL=20060402T070000Z", "END:DAYLIGHT",
        "BEGIN:STANDARD", "TZOFFSETFROM:-0400", "TZOFFSETTO:-0500", "DTSTART:19671029T020000",
        "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU;UNTIL=20061029T060000Z", "END:STANDARD",
        "BEGIN:DAYLIGHT", "TZOFFSETFROM:-0500", "TZOFFSETTO:-0400", "DTSTART:20070311T020000",
        "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU", "END:DAYLIGHT",
        "BEGIN:STANDARD", "TZOFFSETFROM:-0400", "TZOFFSETTO:-0500", "DTSTART:20071104T020000",
        "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU", "END:STANDARD", "END:VTIMEZONE"].join("\r\n") + "\r\n"
    function zoned(zone, ...events) {
        return ics(...events).replace("BEGIN:VCALENDAR\r\n", "BEGIN:VCALENDAR\r\n" + zone);
    }
    function utc(y, m, d, h, min) { return Date.UTC(y, m - 1, d, h, min ?? 0); }
    function test_tzid_times() {
        const e = Calendar.icsEvents(zoned(newYork,
            ["SUMMARY:Summer", "DTSTART;TZID=America/New_York:20260710T090000", "DTEND;TZID=America/New_York:20260710T100000"],
            ["SUMMARY:Winter", "DTSTART;TZID=\"America/New_York\":20261210T090000"],
            ["SUMMARY:Late October", "DTSTART;TZID=America/New_York:20261028T090000"],
            ["SUMMARY:Elsewhere", "DTSTART;TZID=Mars/Olympus:20261210T090000"],
            ["SUMMARY:Long ago", "DTSTART;TZID=America/New_York:19500601T090000"]));
        compare(e[0].start.getTime(), utc(2026, 7, 10, 13), "summer: -4");
        compare(e[0].end.getTime(), utc(2026, 7, 10, 14), "DTEND in the zone too");
        compare(e[1].start.getTime(), utc(2026, 12, 10, 14), "winter: -5; a quoted TZID");
        compare(e[2].start.getTime(), utc(2026, 10, 28, 13), "still summer: the old October rule ended in 2006");
        compare(e[3].start.getTime(), new Date(2026, 11, 10, 9).getTime(), "a TZID the file does not describe is local");
        compare(e[3].zone, null);
        compare(e[4].start.getTime(), utc(1950, 6, 1, 13), "before every part: the earliest part's TZOFFSETFROM");
    }
    function test_tzid_zone_after_events_and_fixed_zones() {
        // the VTIMEZONE may come after the events; a zone with one part and no rule is a fixed offset
        const text = ics(["SUMMARY:Standup", "DTSTART;TZID=Asia/Kolkata:20261105T100000"])
            .replace("END:VCALENDAR", ["BEGIN:VTIMEZONE", "TZID:Asia/Kolkata", "BEGIN:STANDARD", "TZOFFSETFROM:+0530",
                                       "TZOFFSETTO:+0530", "DTSTART:19700101T000000", "END:STANDARD", "END:VTIMEZONE",
                                       "END:VCALENDAR"].join("\r\n"));
        compare(Calendar.icsEvents(text)[0].start.getTime(), utc(2026, 11, 5, 4, 30));
        // a rule written the old way: the second Sunday as BYMONTHDAY=8..14 with BYDAY=SU
        const old = ["BEGIN:VTIMEZONE", "TZID:Old", "BEGIN:STANDARD", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0100",
                     "DTSTART:19701011T030000", "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=SU;BYMONTHDAY=8,9,10,11,12,13,14",
                     "END:STANDARD", "BEGIN:DAYLIGHT", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0200",
                     "DTSTART:19700405T020000", "RRULE:FREQ=YEARLY;BYMONTH=4;BYDAY=1SU", "END:DAYLIGHT",
                     "END:VTIMEZONE"].join("\r\n") + "\r\n";
        const e = Calendar.icsEvents(zoned(old, ["SUMMARY:A", "DTSTART;TZID=Old:20261010T120000"],
                                                ["SUMMARY:B", "DTSTART;TZID=Old:20261011T120000"]));
        compare(e[0].start.getTime(), utc(2026, 10, 10, 10), "before the second Sunday of October: +2");
        compare(e[1].start.getTime(), utc(2026, 10, 11, 11), "on it: +1");
        // rules on a date: the part's own day
        const dated = ["BEGIN:VTIMEZONE", "TZID:Dated", "BEGIN:DAYLIGHT", "TZOFFSETFROM:+0330", "TZOFFSETTO:+0430",
                       "DTSTART:19700321T000000", "RRULE:FREQ=YEARLY", "END:DAYLIGHT", "BEGIN:STANDARD",
                       "TZOFFSETFROM:+0430", "TZOFFSETTO:+0330", "DTSTART:19700921T000000",
                       "RRULE:FREQ=YEARLY;BYMONTH=9;BYMONTHDAY=21", "END:STANDARD", "END:VTIMEZONE"].join("\r\n") + "\r\n";
        const f = Calendar.icsEvents(zoned(dated, ["SUMMARY:A", "DTSTART;TZID=Dated:20260701T120000"],
                                                  ["SUMMARY:B", "DTSTART;TZID=Dated:20261001T120000"]));
        compare(f[0].start.getTime(), utc(2026, 7, 1, 7, 30), "after March 21: +4:30");
        compare(f[1].start.getTime(), utc(2026, 10, 1, 8, 30), "after September 21: +3:30");
    }
    function test_tzid_repeats_on_the_zone_clock() {
        // 9:00 in New York each Monday, across the change on Nov 1 2026; the EXDATE in the zone leaves Nov 9 out
        const e = Calendar.icsEvents(zoned(newYork, ["SUMMARY:Sync", "UID:y",
            "DTSTART;TZID=America/New_York:20261026T090000", "RRULE:FREQ=WEEKLY;COUNT=4",
            "EXDATE;TZID=America/New_York:20261109T090000"],
            ["SUMMARY:Sync (moved)", "UID:y", "RECURRENCE-ID;TZID=America/New_York:20261116T090000",
             "DTSTART;TZID=America/New_York:20261116T110000"]));
        const o = Calendar.occurrences(e, day(2026, 10, 1), day(2026, 12, 1));
        compare(o.map(x => x.title + "@" + new Date(x.start).toISOString()).join(","),
                "Sync@2026-10-26T13:00:00.000Z,Sync@2026-11-02T14:00:00.000Z,Sync (moved)@2026-11-16T16:00:00.000Z");
    }

    // ---- calendar addresses (D94) ----
    function test_feed_addresses() {
        compare(Calendar.feedUrl("webcal://p01-calendars.icloud.com/x.ics"), "https://p01-calendars.icloud.com/x.ics");
        compare(Calendar.feedUrl(" https://calendar.google.com/calendar/ical/a%40gmail.com/private-k/basic.ics "),
                "https://calendar.google.com/calendar/ical/a%40gmail.com/private-k/basic.ics", "trimmed");
        compare(Calendar.feedUrl("http://127.0.0.1:8000/c.ics"), "http://127.0.0.1:8000/c.ics");
        compare(Calendar.feedUrl("ftp://x/c.ics"), "");
        compare(Calendar.feedUrl("file:///etc/passwd"), "", "never a local file");
        verify(Calendar.isCalendar("BEGIN:VCALENDAR\r\nEND:VCALENDAR"));
        verify(Calendar.isCalendar("\r\n  begin:vcalendar"));
        verify(!Calendar.isCalendar("<html>Sign in</html>"));
        verify(!Calendar.isCalendar(""));
        const a = Calendar.cacheName("https://calendar.google.com/secret-a/basic.ics");
        verify(/^[0-9a-f]{16}$/.test(a), a);
        compare(Calendar.cacheName("https://calendar.google.com/secret-a/basic.ics"), a, "the same each time");
        verify(Calendar.cacheName("https://calendar.google.com/secret-b/basic.ics") !== a);
    }

    // ---- evolution-data-server (D95) ----
    function test_eds_events() {
        const text = '{"calendar":"Work","source":"g1","uid":"a","title":"Standup","start":1793761200,"end":1793763000,"allDay":false}\n' +
                     'not json\n{"title":"no times"}\n\n' +
                     '{"source":"g1","uid":"b","title":"","start":1793800000,"end":1793700000,"allDay":true}\n';
        const e = Calendar.edsEvents(text);
        compare(e.length, 2, "lines that are not events left out");
        compare(e[0].title, "Standup");
        compare(e[0].start.getTime(), 1793761200000);
        compare(e[0].end - e[0].start, 1800000);
        compare(e[0].rule, null, "EDS expands repeats itself");
        compare(e[1].title, "Event", "no title");
        compare(e[1].end.getTime(), e[1].start.getTime(), "an end before the start is the start");
        verify(e[1].allDay);
        compare(Calendar.eventUuid(e[0]), "g1:a");
        compare(Calendar.eventUuid({ source: "", uid: "x" }), "", "an .ics file's event has no calendar to open it in");
        compare(Calendar.edsCommand("/h", new Date(1000), new Date(2500)).join(" "), "/h events 1 3");
        // the day's list keeps the id, so a click opens the event in GNOME Calendar
        const day = Calendar.dayEvents(e, new Date(1793761200000), true, en, ClockText.time);
        compare(day.find(d => d.title === "Standup").uuid, "g1:a");
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
                JSON.stringify([{ title: "Holiday", time: "All day", uuid: "" }, { title: "Pin", time: "08:00", uuid: "" },
                                { title: "Late", time: "23:00 – Nov 5, 01:00", uuid: "" }]));
        compare(Calendar.dayEvents(e, day(2026, 11, 5), false, en, ClockText.time)[0].time, "Nov 4, 11:00 – 1:00",
                "the next day shows when it began");
    }

    // ---- the panel ----
    Component { id: panelComp; CalendarPanel {} }
    // The Columns and Rows an item is in have placed it: they do so at the next polish, and a click before then lands
    // where the item was.
    function laidOut(item) {
        for (let i = item; i; i = i.parent) waitForItemPolished(i);
    }
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
        // one circle each for today and the chosen day, and a dot only under days with events
        const today = findChild(p, "calendarTodayCircle"), day = findChild(p, "calendarDay_2026-11-04");
        verify(today.visible);
        compare(today.mapToItem(p, today.width / 2, 0).x, day.mapToItem(p, day.width / 2, 0).x, "today's circle on today");
        verify(!findChild(p, "calendarChosenCircle").visible, "today chosen: its own circle only");
        const busyDays = p.days.filter(d => p.busy[Calendar.dayKey(d)] === true).map(d => Calendar.dayKey(d));
        const dots = today.parent.children.filter(c => c.objectName === "calendarDot");
        verify(busyDays.length > 0);
        compare(dots.length, busyDays.length, "a dot for each day with events, none for the rest");
        const busy = findChild(p, "calendarDay_" + busyDays[0]);
        verify(dots.some(dot => Math.abs(dot.mapToItem(p, dot.width / 2, 0).x - busy.mapToItem(p, busy.width / 2, 0).x) < 1
                         && dot.mapToItem(p, 0, 0).y > busy.mapToItem(p, 0, 0).y
                         && dot.mapToItem(p, 0, 0).y < busy.mapToItem(p, 0, busy.height).y), "under its day");
    }
    function test_panel_hover_and_chosen_circle() {
        const p = panel({ events: Calendar.icsEvents(sample) });
        const d = findChild(p, "calendarDay_2026-11-12"), hover = findChild(p, "calendarHover");
        mouseMove(d, d.width / 2, d.height / 2);
        tryVerify(() => hover.opacityNow > 0, 2000, "the hover circle shows");
        compare(hover.mapToItem(p, hover.width / 2, 0).x, d.mapToItem(p, d.width / 2, 0).x, "on the day under the pointer");
        compare(hover.mapToItem(p, 0, hover.height / 2).y, d.mapToItem(p, 0, d.height / 2).y);
        mouseClick(d);
        const chosen = findChild(p, "calendarChosenCircle");
        verify(chosen.visible, "another day chosen: its circle");
        compare(chosen.mapToItem(p, chosen.width / 2, 0).x, d.mapToItem(p, d.width / 2, 0).x);
        compare(chosen.mapToItem(p, 0, chosen.height / 2).y, d.mapToItem(p, 0, d.height / 2).y);
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
        // a day of the next month shown in this one's last week moves to that month (once the grid has placed the
        // new month's days: the click goes to the day at that point)
        waitForItemPolished(findChild(p, "calendarDay_2026-12-02").parent);
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
        verify(findChild(p, "calendarEmpty").text.startsWith("No calendars yet"));
        const button = findChild(p, "calendarSettings");
        verify(button.visible);
        const spy = createTemporaryObject(spyComp, root, { target: p, signalName: "settingsRequested" });
        mouseClick(button);
        compare(spy.count, 1);
    }
    function test_panel_opens_events_and_the_app() {
        const eds = Calendar.edsEvents('{"source":"g1","uid":"a","title":"Synced","start":' +
                                       (new Date(2026, 10, 4, 9).getTime() / 1000) + ',"end":' +
                                       (new Date(2026, 10, 4, 10).getTime() / 1000) + ',"allDay":false}');
        const p = panel({ events: Calendar.icsEvents(sample).concat(eds) });
        const opened = createTemporaryObject(spyComp, root, { target: p, signalName: "eventOpened" });
        const app = createTemporaryObject(spyComp, root, { target: p, signalName: "appRequested" });
        compare(p.dayEvents.map(e => e.title).join(), "Holiday,Synced,Gym");
        mouseClick(findChild(p, "calendarEvent_1"));
        compare(opened.count, 1);
        compare(opened.signalArguments[0][0], "g1:a");
        mouseClick(findChild(p, "calendarEvent_0"));
        compare(opened.count, 1, "an .ics file's event opens nothing");
        verify(!findChild(p, "calendarApp").visible, "no GNOME Calendar, no button");
        const before = p.maxHeight;
        p.hasApp = true;
        verify(findChild(p, "calendarApp").visible);
        verify(p.maxHeight > before, "room for the button");
        waitForItemPolished(findChild(p, "calendarApp").parent);     // the column has placed it
        mouseClick(findChild(p, "calendarApp"));
        compare(app.count, 1);
    }
    function test_panel_note() {
        const p = panel();
        const note = findChild(p, "calendarNote");
        verify(!note.visible);
        const before = p.maxHeight;
        p.note = "A calendar could not be refreshed: showing its saved events.";
        verify(note.visible);
        verify(p.maxHeight > before, "the window makes room for it");
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

    // ---- adding an event (D101) ----
    function test_add_helpers() {
        compare(Calendar.parseClock("9"), 540);
        compare(Calendar.parseClock("09:30"), 570);
        compare(Calendar.parseClock("9.30"), 570);
        compare(Calendar.parseClock("930"), 570);
        compare(Calendar.parseClock("21:05"), 1265);
        compare(Calendar.parseClock("9pm"), 1260);
        compare(Calendar.parseClock("12 AM"), 0);
        compare(Calendar.parseClock("12:15 p.m."), 735);
        compare(Calendar.parseClock("9:30 PM"), 1290);
        for (const bad of ["", "25", "9:60", "13pm", "noon", "9:3"])
            compare(Calendar.parseClock(bad), -1, bad);
        compare(Calendar.clockText(570, true), "9:30");
        compare(Calendar.clockText(1290, false), "9:30 PM");
        compare(Calendar.clockText(0, false), "12:00 AM");
        const now = new Date(2026, 10, 4, 9, 30);
        compare(Calendar.suggestedStart(now, now), 600, "today: the next full hour");
        compare(Calendar.suggestedStart(new Date(2026, 10, 4, 23, 30), new Date(2026, 10, 4, 23, 30)), 1380, "never past 23:00");
        compare(Calendar.suggestedStart(new Date(2026, 10, 5), now), 540, "another day: 9:00");
        const day = new Date(2026, 10, 12);
        let t = Calendar.newEventTimes(day, false, "9:30", "10:15");
        compare(t.start.getTime(), new Date(2026, 10, 12, 9, 30).getTime());
        compare(t.end.getTime(), new Date(2026, 10, 12, 10, 15).getTime());
        t = Calendar.newEventTimes(day, false, "23:00", "0:00");
        compare(t.end.getTime(), new Date(2026, 10, 13).getTime(), "midnight: the end of the day");
        compare(Calendar.newEventTimes(day, false, "10", "9").error, "It ends before it starts");
        compare(Calendar.newEventTimes(day, false, "x", "9").error, "Type a start time, like 9:30");
        compare(Calendar.newEventTimes(day, false, "9", "").error, "Type an end time, like 10:30");
        t = Calendar.newEventTimes(day, true, "x", "y");
        compare([t.start.getTime(), t.end.getTime()].join(), [new Date(2026, 10, 12).getTime(), new Date(2026, 10, 13).getTime()].join(),
                "all day: the day, to the next one's start; the times not read");
        compare(Calendar.addCommand("h", "src", false, new Date(1793800000000), new Date(1793803600000), "A b").join("|"),
                "h|add|src|timed|1793800000|1793803600|A b");
        const cals = Calendar.edsCalendars([
            '{"source":"birthdays","name":"Birthdays","backend":"contacts","default":false}',
            '{"source":"w","name":"Work","color":"#f00","backend":"caldav","default":false}', "not json",
            '{"source":"p","name":"Personal","backend":"local","default":true}'].join("\n"));
        compare(cals.map(c => c.source).join(), "p,w", "the default first; Birthdays left out");
    }

    readonly property var twoCalendars: [{ source: "p", name: "Personal", color: "", isDefault: true },
                                         { source: "w", name: "Work", color: "#f00", isDefault: false }]
    function test_add_form() {
        const none = panel();
        verify(!findChild(none, "calendarAdd").visible, "no calendar that takes events: no +");
        const p = panel({ calendars: twoCalendars });
        const asked = createTemporaryObject(spyComp, root, { target: p, signalName: "addRequested" });
        p.forceActiveFocus();
        mouseClick(findChild(p, "calendarDay_2026-11-12"));
        const add = findChild(p, "calendarAdd");
        verify(add.visible);
        mouseClick(add);
        verify(p.composing);
        verify(findChild(p, "calendarCompose").visible);
        verify(!findChild(p, "calendarEmpty").visible, "the form in place of the day's events");
        verify(!add.visible);
        const title = findChild(p, "calendarTitleField");
        tryVerify(() => title.focused, 1000, "the title takes the keys");
        compare(findChild(p, "calendarStartField").text, "9:00", "another day: 9:00");
        compare(findChild(p, "calendarEndField").text, "10:00", "an hour long");
        compare(findChild(p, "calendarChoose").text, "Personal", "the default calendar");
        verify(p.height <= p.maxHeight + 0.5, "the form fits the window: " + p.height + " within " + p.maxHeight);
        // keys go to the field, not to the days
        keyClick(Qt.Key_Down);
        compare(Calendar.dayKey(p.selected), "2026-11-12");
        keyClick(Qt.Key_Return);
        compare(asked.count, 0, "no title: nothing asked");
        compare(findChild(p, "calendarComposeError").text, "Give it a title");
        for (const c of "Dentist") keyClick(c);
        const end = findChild(p, "calendarEndField");
        end.text = "8:00";
        keyClick(Qt.Key_Return);
        compare(asked.count, 0);
        compare(findChild(p, "calendarComposeError").text, "It ends before it starts");
        end.text = "10:30";
        // another calendar, from the menu
        const ch = findChild(p, "calendarChoose");
        laidOut(ch);
        mouseClick(ch);
        tryVerify(() => findChild(p, "calendarChoice_w") !== null);
        const work = findChild(p, "calendarChoice_w");
        tryCompare(work, "opacity", 1);
        mouseClick(work);
        compare(findChild(p, "calendarChoose").text, "Work");
        mouseClick(findChild(p, "calendarSave"));
        compare(asked.count, 1);
        const a = asked.signalArguments[0];
        compare([a[0], a[1], a[4]].join(), "w,false,Dentist");
        compare(a[2].getTime(), new Date(2026, 10, 12, 9).getTime());
        compare(a[3].getTime(), new Date(2026, 10, 12, 10, 30).getTime());
        // the owner's answer: a failure keeps the form, with why
        p.saving = true;
        compare(findChild(p, "calendarSave").text, "Saving…");
        p.saving = false;
        p.addFinished(false, "w is read-only");
        verify(p.composing);
        compare(findChild(p, "calendarComposeError").text, "w is read-only");
        p.addFinished(true, "");
        verify(!p.composing, "added: the form closes");
        verify(findChild(p, "calendarEmpty").visible);
        // all day, and Escape cancels
        mouseClick(add);
        compare(title.text, "", "a fresh form");
        compare(findChild(p, "calendarChoose").text, "Work", "the calendar chosen last");
        mouseClick(findChild(p, "calendarAllDay"));
        verify(!findChild(p, "calendarStartField").visible, "all day: no times");
        title.input.forceActiveFocus();
        for (const c of "Trip") keyClick(c);
        keyClick(Qt.Key_Return);
        compare(asked.count, 2);
        const b = asked.signalArguments[1];
        compare(b[1], true);
        compare(b[2].getTime(), new Date(2026, 10, 12).getTime());
        compare(b[3].getTime(), new Date(2026, 10, 13).getTime());
        keyClick(Qt.Key_Escape);
        verify(!p.composing, "Escape closes the form, not the calendar");
        keyClick(Qt.Key_Right);
        compare(Calendar.dayKey(p.selected), "2026-11-13", "the arrows move the day again");
    }
    function test_add_one_calendar() {
        const p = panel({ calendars: [twoCalendars[1]] });
        mouseClick(findChild(p, "calendarAdd"));
        verify(!findChild(p, "calendarChoose").visible, "one calendar: no choice to show");
        compare(findChild(p, "calendarStartField").text, "10:00", "today: the next full hour");
    }

    // ---- the clock's open look ----
    Component { id: pillComp; ClockPill {} }
    function test_clock_open() {
        const pill = createTemporaryObject(pillComp, root, { now: new Date(2026, 10, 4, 9, 30) });
        compare(pill.color, Colors.surfaceContainer);
        pill.open = true;
        tryCompare(pill, "color", Colors.secondaryContainer);
    }
}
