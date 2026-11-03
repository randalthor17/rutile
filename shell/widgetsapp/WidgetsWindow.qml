// The Widgets app's window (plan 4.5, D82): an ordinary app window, created only while open (D31), like Settings.
// It reads the templates and the user's widgets (WidgetLibrary) and does what the app asks. Using a template copies
// it to $XDG_CONFIG_HOME/rutile/widgets under a name not taken yet, allows the web address it reads (Settings >
// Widgets), and asks the shell to put it on the desktop and preview it; then it opens in the editor
// (`widgets.editor`, or xdg-open). The shell does the placing, so this window stays free of the desktop.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.desktop
import qs.services
import "Gallery.js" as Gallery

FloatingWindow {
    id: root

    readonly property alias app: app
    property string lastCreated: ""         // the last copy made, for the tests

    signal finished()
    signal placeRequested(string path)
    signal previewRequested(string path)

    function edit(path) {
        Quickshell.execDetached(Gallery.editorCommand(Settings.value("widgets.editor"), path));
        root.previewRequested(path);
    }
    // Copies template `path`; the rest happens once the copy is there.
    function use(path) {
        if (copier.running)
            return false;
        const spec = templates.specs[path] ?? null;
        copier.spec = spec;
        copier.command = ["sh", "-c", 'd=$1; f="$d/$2.json"; n=2; while [ -e "$f" ]; do f="$d/$2-$n.json"; n=$((n+1)); done; ' +
                          'mkdir -p "$d" && cp "$3" "$f" && printf %s "$f"', "sh", mine.userDir, Gallery.fileStem(spec, path), path];
        copier.running = true;
        return true;
    }
    function created(path) {
        if (path === "")
            return;
        lastCreated = path;
        const prefix = Gallery.fetches(copier.spec);
        const allow = Settings.value("widgets.httpAllow") ?? [];
        if (prefix !== "" && allow.indexOf(prefix) < 0)
            Settings.set("widgets.httpAllow", allow.concat([prefix]));
        root.placeRequested(path);
        root.edit(path);
        app.openCategory("yours");
        mine.scan();
    }

    title: "Widgets"
    implicitWidth: 1180
    implicitHeight: 780
    minimumSize: Qt.size(720, 480)
    color: Colors.surfaceContainerLow
    onClosed: root.finished()

    WidgetLibrary {
        id: templates
        dirs: [templatesDir]
        paths: available.map(e => e.path)        // 30 small files, so Use knows each one's name
        Component.onCompleted: scan()
    }
    WidgetLibrary {
        id: mine
        dirs: [userDir]
        paths: available.map(e => e.path)
        Component.onCompleted: scan()
    }
    Process {
        id: copier
        property var spec: null
        stdout: StdioCollector { onStreamFinished: root.created(text.trim()) }
    }

    WidgetsApp {
        id: app
        anchors.fill: parent
        templates: templates.available
        mine: mine.available
        specs: Object.assign({}, templates.specs, mine.specs)
        allow: Settings.value("widgets.httpAllow") ?? []
        userDir: mine.userDir.replace(Quickshell.env("HOME"), "~")
        onCurrentCategoryChanged: if (showingMine) mine.scan()
        onUseRequested: path => root.use(path)
        onEditRequested: path => root.edit(path)
        onPlaceRequested: path => root.placeRequested(path)
        onFolderRequested: Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", mine.userDir])
    }
}
