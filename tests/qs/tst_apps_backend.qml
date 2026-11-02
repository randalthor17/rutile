// The Apps page's backend (plan 5.2, D71) with fixture desktop files (tests/qs/mime): the user's data folder
// before the system's (its Chromium's name wins), a NoDisplay app offered only as the default, a Hidden one never;
// defaults read in the spec's order (the system's mimeapps.list until the user has one); choosing writes the
// user's mimeapps.list, keeping its other groups; a home-manager link is never written.
// env XDG_DATA_HOME=@WS@/mime/user
// env XDG_DATA_DIRS=@WS@/mime/system
// env XDG_CONFIG_DIRS=@WS@/mime/no-config-dirs
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services      // as the shell has it: Quickshell makes the qs modules something imports

ShellRoot {
    id: root
    property int stage: 0
    property string out: ""
    readonly property string list: Quickshell.env("XDG_CONFIG_HOME") + "/mimeapps.list"
    QsTest { id: t }
    Loader { id: backend }
    Process {
        id: sh
        stdout: StdioCollector { onStreamFinished: root.out = text }
    }
    function run(script) {
        sh.command = ["sh", "-c", script, "sh", root.list];
        sh.running = true;
    }
    function kind(id) {
        return backend.item.kinds.find(k => k.id === id);
    }
    // the user's file, with a group of its own to keep
    Component.onCompleted: run('mkdir -p "$(dirname "$1")"; printf "[Added Associations]\\ntext/plain=foo.desktop;\\n" > "$1"')
    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (sh.running) return;
            const b = backend.item;
            switch (root.stage) {
            case 0:
                backend.source = Qt.resolvedUrl("settingsapp/pages/AppsBackend.qml");
                break;
            case 1: {
                if (!b || !b.available) return;
                const br = root.kind("browser");
                t.compare(br.apps.map(a => a.name).join(), "Chromium (mine),Firefox", "the user's file wins; no NoDisplay or Hidden");
                t.compare(br.current, "chromium.desktop", "the system's mimeapps.list");
                t.compare(root.kind("files").current, "org.gnome.Nautilus.desktop");
                t.compare(root.kind("pdf").apps.length, 0, "nothing for PDFs");
                t.verify(!b.managed);
                b.setDefault("browser", "firefox.desktop");
                break;
            }
            case 2:
                if (root.kind("browser").current !== "firefox.desktop") return;
                root.run('cat "$1"');
                break;
            case 3:
                t.verify(root.out.indexOf("[Added Associations]\ntext/plain=foo.desktop;") >= 0, "its other group kept: " + root.out);
                for (const m of ["x-scheme-handler/https", "x-scheme-handler/http", "text/html"])
                    t.verify(root.out.indexOf(m + "=firefox.desktop;") >= 0, m + ": " + root.out);
                t.compare(b.error, "");
                // home-manager's file: a link
                root.run('mv "$1" "$1.real"; ln -s "$1.real" "$1"');
                break;
            case 4:
                b.refresh();
                break;
            case 5:
                if (!b.managed) return;
                b.setDefault("browser", "chromium.desktop");
                t.verify(b.error.indexOf("home-manager") >= 0, "says where to set it: " + b.error);
                break;
            case 6:
                // time for a write, were one started
                root.run('sleep 0.5; readlink "$1"; cat "$1"');
                break;
            case 7:
                t.verify(root.out.indexOf("=firefox.desktop;") >= 0 && root.out.indexOf("mimeapps.list.real") >= 0,
                         "the link and its file untouched: " + root.out);
                t.done();
                break;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
