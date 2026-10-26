// Tiny test helper for tests that need Quickshell (tests/qs/, run by `tools/qtws.py test-qs`).
// qmltestrunner cannot load Quickshell types, so these run as a shell under `quickshell` offscreen:
// each check logs a line, and done() exits with the number of failures.
import QtQuick

QtObject {
    property int failures: 0
    property int checks: 0

    function verify(cond, msg) {
        checks++;
        if (!cond) {
            failures++;
            console.log("QSTEST FAIL: " + msg);
        }
    }

    function compare(actual, expected, msg) {
        verify(actual === expected, msg + ": got " + actual + ", expected " + expected);
    }

    function done() {
        console.log("QSTEST done checks=" + checks + " failures=" + failures);
        // Qt.exit() before the event loop runs (e.g. from Component.onCompleted) is ignored: defer it.
        var code = failures > 0 ? 1 : 0;
        Qt.callLater(function () { Qt.exit(code); });
    }
}
