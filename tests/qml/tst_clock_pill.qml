import QtQuick
import QtTest
import qs.common
import qs.bar
import "../qs/bar/ClockText.js" as ClockText

TestCase {
    id: root
    name: "ClockPill"
    width: 400
    height: 200
    visible: true
    when: windowShown

    Component { id: pillComp; ClockPill {} }

    function at(h, m) { return new Date(2026, 9, 9, h, m); }      // Fri, Oct 9 2026

    function test_time_text() {
        compare(ClockText.time(at(8, 55), false), "8:55");
        compare(ClockText.time(at(20, 5), false), "8:05", "no AM/PM, as Googlebook");
        compare(ClockText.time(at(0, 0), false), "12:00", "midnight is 12");
        compare(ClockText.time(at(12, 30), false), "12:30", "noon is 12");
        compare(ClockText.time(at(20, 55), true), "20:55");
        compare(ClockText.time(at(8, 5), true), "08:05");
        compare(ClockText.time(at(0, 0), true), "00:00");
    }

    function test_date_text_and_clock_kind() {
        compare(ClockText.date(at(8, 55), Qt.locale("en_US")), "Fri, Oct 9");
        verify(!ClockText.uses24h("h:mm AP"));
        verify(!ClockText.uses24h("h:mm a"));
        verify(ClockText.uses24h("HH:mm"));
        verify(ClockText.uses24h(Qt.locale("de_DE").timeFormat(Locale.ShortFormat)));
        verify(!ClockText.uses24h(Qt.locale("en_US").timeFormat(Locale.ShortFormat)));
    }

    function test_pill_shows_time_and_date() {
        var pill = createTemporaryObject(pillComp, root, { now: at(8, 55), use24h: false, x: 20, y: 20 });
        waitForRendering(pill);
        var text = findChild(pill, "clockText");
        compare(pill.timeText, "8:55");
        compare(text.text, "8:55 " + ClockText.date(at(8, 55), Qt.locale()));
        compare(pill.height, Spacing.xl, "as tall as the status pill");
        verify(pill.width > text.implicitWidth, "padded");
        var narrow = pill.width;
        pill.now = at(20, 55);
        compare(pill.timeText, "8:55", "12-hour");
        pill.use24h = true;
        compare(pill.timeText, "20:55");
        tryVerify(function () { return pill.width > narrow; }, 1000, "the pill follows its text");
        verify(Qt.colorEqual(pill.color, Colors.surfaceContainer));
    }
}
