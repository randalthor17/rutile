// The shell's widget check (plan 4.6, D85): WidgetCheck.js finds what tools/widget_check.py finds, the same
// problems at the same paths in the same words, on broken widgets (tests/widget_check_cases.py) and on every example
// and template; and its text report.
import QtQuick
import QtTest
import "../qs/widgethost/WidgetCheck.js" as Check

TestCase {
    name: "WidgetCheck"

    function readJson(rel) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }

    function test_the_same_problems_as_the_python() {
        const cases = readJson("../data/widget_check_cases.json");
        verify(cases.length > 60, "the cases were written: " + cases.length);
        let broken = 0;
        for (const c of cases) {
            compare(JSON.stringify(Check.check(c.widget)), JSON.stringify(c.problems), c.name);
            if (c.problems.length) broken++;
        }
        verify(broken >= 25, "and most broken ones find something: " + broken);
    }

    function test_text_and_report() {
        const ok = Check.checkText('{"version": 1, "name": "A", "root": {"type": "chip", "label": "{{clock.time}}"}}');
        compare(ok.ok, true);
        compare(ok.problems.length, 0);
        compare(Check.report("/w/a.json", ok), "ok: /w/a.json");
        const bad = Check.checkText("{oops");
        compare(bad.ok, false);
        compare(bad.problems[0].path, "$");
        verify(bad.problems[0].message.indexOf("not valid JSON: ") === 0, bad.problems[0].message);
        const two = Check.checkText('{"version": 2, "name": "A", "root": {"type": "chip"}}');
        compare(Check.report("/w/b.json", two), "/w/b.json: $.version: must be 1, got 2\n" +
                "/w/b.json: $.root: missing required field 'label'\nFAILED: /w/b.json (2 problem(s))");
    }
}
