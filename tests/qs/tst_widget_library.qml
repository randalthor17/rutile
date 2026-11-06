// The widget files behind the desktop grid (plan 4.4, D81), in the shell: a placed file is read and read again
// when it is saved, one that is not JSON or not there is null, and the scan lists the user's widgets by name.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.desktop

ShellRoot {
    id: root
    readonly property string dir: Settings.configDir + "/widgets"
    property int stage: 0
    QsTest { id: t }

    Process {
        id: setup
        running: true
        command: ["sh", "-c", 'mkdir -p "$1" && printf %s "{\\"version\\":1,\\"name\\":\\"First\\",\\"size\\":{\\"w\\":2,\\"h\\":6}}" > "$1/a.json" && ' +
                  'printf "{oops" > "$1/b.json"', "sh", root.dir]
    }
    Process {
        id: rewrite
        command: ["sh", "-c", 'printf %s "{\\"version\\":1,\\"name\\":\\"Second\\"}" > "$1/a.json"', "sh", root.dir]
    }

    WidgetLibrary {
        id: library
        paths: root.stage >= 1 ? [root.dir + "/a.json", root.dir + "/b.json", root.dir + "/none.json"] : []
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (root.stage === 0 && !setup.running && ticks >= 2) {
                root.stage = 1;
                library.scan();
                ticks = 0;
                return;
            }
            const a = library.specs[root.dir + "/a.json"];
            if (root.stage === 1 && ((a && library.available.length > 0 && Object.keys(library.specs).length === 3) || ticks > 20)) {
                t.compare(a?.name, "First", "a placed file is read");
                t.compare(library.specs[root.dir + "/b.json"], null, "not JSON: null");
                t.compare(library.specs[root.dir + "/none.json"], null, "not there: null");
                const mine = library.available.filter(w => w.path.startsWith(root.dir));
                t.compare(JSON.stringify(mine), JSON.stringify([{ path: root.dir + "/a.json", name: "First", size: { w: 2, h: 6 } },
                                                                 { path: root.dir + "/b.json", name: "b", size: { w: 4, h: 3 } }]),
                          "the user's widgets, by name, with the size each asks for");
                t.compare(JSON.stringify(library.sizeOf(root.dir + "/a.json")), '{"w":2,"h":6}', "a file's size, read at once");
                t.compare(JSON.stringify(library.sizeOf(root.dir + "/b.json")), '{"w":4,"h":3}', "not JSON: the usual");
                t.compare(JSON.stringify(library.sizeOf(root.dir + "/none.json")), '{"w":4,"h":3}', "not there: the usual");
                rewrite.running = true;
                root.stage = 2;
                ticks = 0;
                return;
            }
            if (root.stage === 2 && (a?.name === "Second" || ticks > 20)) {
                t.compare(a?.name, "Second", "read again when saved");
                library.paths = [root.dir + "/a.json"];
                t.compare(Object.keys(library.specs).join(), root.dir + "/a.json", "a file no longer placed is dropped");
                t.done();
            }
        }
    }
}
