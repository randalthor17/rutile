// Typing in other languages through fcitx5 (D118), which Rutile depends on (with m17n's input methods; more come as
// fcitx5 addons the user installs). The shell starts fcitx5 when none is running a few seconds after it starts (a
// system that starts its own, as NixOS's i18n.inputMethod does, wins; `RUTILE_FCITX5` names the binary), and talks
// to it over D-Bus with busctl: the current group's input methods, the one in use, switching. fcitx5 reports no
// switch over that interface, so shell.qml calls refresh() when fcitx5's tray icon changes (it changes with every
// switch), and the service reads again after its own switches. `available` is false until fcitx5 answers.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "InputMethod.js" as Ime

Singleton {
    id: root

    property bool available: false
    property var methods: []            // [{id, name, label}], the current group's
    property string current: ""         // fcitx5's current input method; "" while no window takes text
    readonly property var shown: Ime.shown(methods, current)
    readonly property string binary: Quickshell.env("RUTILE_FCITX5") || "fcitx5"
    readonly property string configTool: Quickshell.env("RUTILE_FCITX5_CONFIGTOOL") || "fcitx5-configtool"
    property bool started: false        // the shell started fcitx5 itself
    property int tries: 0

    function refresh() {
        run(Ime.call("CurrentInputMethodGroup"), (ok, text) => {
            if (!ok) {
                root.available = false;
                return;
            }
            const group = Ime.string(text);
            run(Ime.call("FullInputMethodGroupInfo", "s", [group]), (ok2, text2) => {
                if (ok2) root.methods = Ime.methods(text2);
            });
            run(Ime.call("CurrentInputMethod"), (ok3, text3) => {
                if (!ok3) return;
                root.current = Ime.string(text3);
                root.available = true;
            });
        });
    }
    function set(id) {
        if (!available || !methods.some(m => m.id === id)) return false;
        current = id;
        run(Ime.call("SetCurrentIM", "s", [id]), () => root.refresh());
        return true;
    }
    function next() {
        return set(Ime.next(methods, current));
    }
    function configure() {
        Quickshell.execDetached([configTool]);
    }

    // one busctl at a time, each with what to do with its answer: (ok, stdout)
    property var _queue: []
    property var _running: null
    function run(command, done) {
        _queue = _queue.concat([{ command: command, done: done }]);
        _next();
    }
    function _next() {
        if (_running || _queue.length === 0) return;
        _running = _queue[0];
        _queue = _queue.slice(1);
        bus.command = _running.command;
        bus.running = true;
    }
    Process {
        id: bus
        stdout: StdioCollector { id: answer }
        onExited: code => {
            const job = root._running;
            root._running = null;
            if (job) job.done(code === 0, answer.text);
            root._next();
        }
    }

    // Is fcitx5 there? Asked at start; when it is not, asked again after a grace period, then it is started.
    Component.onCompleted: refresh()
    Timer {
        interval: 4000
        running: !root.available && root.tries < 8
        repeat: true
        onTriggered: {
            root.tries++;
            if (root.tries === 1 && !root.available && !root.started) {
                root.started = true;
                Quickshell.execDetached([root.binary, "-d"]);
            }
            root.refresh();
        }
    }
}
