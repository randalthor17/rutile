// The shell's widget file check (plan 4.6, D85): a good file, a broken one, one changed between two checks, a
// missing one and one that is not JSON.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.widgethost

ShellRoot {
    id: root
    readonly property string dir: Quickshell.env("HOME")
    QsTest { id: t }
    WidgetChecker { id: checker }

    Process {
        id: write
        running: true
        command: ["sh", "-c", 'printf %s "{\\"version\\":1,\\"name\\":\\"A\\",\\"root\\":{\\"type\\":\\"chip\\",\\"label\\":\\"{{clock.time}}\\"}}" > "$1/good.json" && ' +
                  'printf %s "{\\"version\\":1,\\"name\\":\\"B\\",\\"root\\":{\\"type\\":\\"chip\\"}}" > "$1/bad.json" && printf "{oops" > "$1/junk.json"',
                  "sh", root.dir]
        onExited: {
            const good = checker.check(root.dir + "/good.json");
            t.compare(good.ok, true, "a good widget: " + JSON.stringify(good.problems));
            const bad = checker.check(root.dir + "/bad.json");
            t.compare(JSON.stringify(bad), JSON.stringify({ ok: false, problems: [{ path: "$.root", message: "missing required field 'label'" }] }));
            t.compare(checker.report(root.dir + "/bad.json"),
                      root.dir + "/bad.json: $.root: missing required field 'label'\nFAILED: " + root.dir + "/bad.json (1 problem(s))");
            t.compare(checker.check(root.dir + "/none.json").problems[0].message, "file not found");
            t.verify(checker.check(root.dir + "/junk.json").problems[0].message.indexOf("not valid JSON") === 0);
            fix.running = true;
        }
    }
    Process {
        id: fix
        command: ["sh", "-c", 'cp "$1/good.json" "$1/bad.json"', "sh", root.dir]
        onExited: {
            t.compare(checker.check(root.dir + "/bad.json").ok, true, "changed since the last check: read again");
            t.done();
        }
    }
}
