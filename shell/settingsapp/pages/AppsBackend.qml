// The Apps page's backend (AppsPage.qml has the interface): the desktop files and mimeapps.list files, read with
// one shell script (Apps.SCAN) when the page opens and after each change (the window loads this only while the
// page is open, D31). A default is set in the user's $XDG_CONFIG_HOME/mimeapps.list, the other groups and keys
// kept; when that file is home-manager's (a link into the store, xdg.mimeApps) nothing is written and the page
// says to set it there.
import QtQuick
import Quickshell
import Quickshell.Io
import "Apps.js" as Apps

Item {
    id: root

    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    property var parsed: ({ entries: {}, lists: [] })
    property bool available: false
    readonly property bool managed: Apps.userList(parsed)?.link ?? false
    property string error: ""
    // [{id, title, icon, current (an app id or ""), apps: [{id, name, icon}]}]
    readonly property var kinds: Apps.KINDS.map(k => ({
        id: k.id, title: k.title, icon: k.icon, current: Apps.kindDefault(parsed, k),
        apps: Apps.candidates(parsed, k).map(e => ({ id: e.id, name: e.name, icon: e.icon }))
    }))

    function refresh() {
        if (!scan.running) scan.running = true;
    }
    function setDefault(kindId, appId) {
        const kind = Apps.KINDS.find(k => k.id === kindId);
        const user = Apps.userList(parsed);
        if (!kind || !user || !parsed.entries[appId]) return;
        if (user.link) {
            error = "Your mimeapps.list comes from home-manager: set this in xdg.mimeApps there";
            return;
        }
        write.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")" && printf "%s" "$1" > "$2.rutile-tmp" && mv "$2.rutile-tmp" "$2"',
                         "sh", Apps.withDefault(user.text, kind.mimes, appId), user.path];
        write.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: scan
        command: ["sh", "-c", Apps.SCAN, "sh", root.configDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parsed = Apps.parse(text);
                root.available = true;
            }
        }
    }
    Process {
        id: write
        stderr: StdioCollector { id: writeErr }
        onExited: code => {
            root.error = code === 0 ? "" : "Could not write mimeapps.list: " + writeErr.text.trim();
            root.refresh();
        }
    }
}
