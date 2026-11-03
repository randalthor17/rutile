// Checks a widget file where the shell runs (plan 4.6, D85): reads it at once (the IPC answer needs the result) and
// checks it with WidgetCheck.js, the port of tools/widget_check.py. For `rutile-shell widgets check` and `install`.
import QtQuick
import Quickshell
import Quickshell.Io
import "WidgetCheck.js" as Check

Scope {
    id: root

    // {ok, problems: [{path, message}]}
    function check(path) {
        file.path = "";                     // read again, even the same file just checked
        file.path = path;
        const text = file.text();
        if (!file.loaded)
            return { ok: false, problems: [{ path: "$", message: "file not found" }] };
        return Check.checkText(text);
    }
    function report(path) {
        return Check.report(path, check(path));
    }

    FileView {
        id: file
        blockAllReads: true
        printErrors: false
    }
}
