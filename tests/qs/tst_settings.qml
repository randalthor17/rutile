// Settings (D45): settings.json under managed.json under the schema's defaults; changes are saved with every key
// kept, a managed key cannot change, an edit on disk applies at once, and state is remembered in state.json.
// env XDG_CONFIG_HOME=@WS@/config/layers
// env XDG_STATE_HOME=@WS@/state
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0

    QsTest { id: t }

    FileView { id: user; path: Settings.configDir + "/settings.json"; blockLoading: true; watchChanges: true; onFileChanged: reload() }
    FileView { id: managed; path: Settings.configDir + "/managed.json"; blockLoading: true }
    // state.json does not exist yet, so there is nothing to watch: read it again until it is there
    FileView { id: state; path: Settings.stateDir + "/state.json"; printErrors: false }

    Component.onCompleted: {
        t.compare(Settings.configDir, Quickshell.env("XDG_CONFIG_HOME") + "/rutile", "the config directory");
        t.compare(Settings.stateDir, Quickshell.env("XDG_STATE_HOME") + "/rutile", "the state directory");
        t.compare(Settings.value("motion.speed"), 2, "from settings.json, on the first frame");
        t.compare(Settings.value("shelf.pins").join(), "firefox", "managed.json wins");
        t.verify(Settings.isManaged("shelf.pins"), "pins are managed");
        t.verify(!Settings.isManaged("motion.speed"), "speed is not");

        t.verify(!Settings.set("shelf.pins", ["kitty"]), "a managed key cannot change");
        t.verify(!Settings.set("motion.speed", 9), "out of range");
        t.verify(!Settings.set("motion.speed", "fast"), "wrong type");
        t.verify(!Settings.set("no.such", 1), "unknown key");
        t.compare(Settings.value("motion.speed"), 2, "refused changes change nothing");

        t.verify(Settings.set("motion.speed", 0.5), "a change");
        t.compare(Settings.value("motion.speed"), 0.5, "applies at once");

        t.compare(Settings.stateValue("launcher.view", "grid"), "grid", "the fallback without state");
        Settings.setState("launcher.view", "list");
        Settings.setState("launcher.other", 1);
        t.compare(Settings.stateValue("launcher.view", "grid"), "list", "state applies at once");
    }

    function check() {
        if (stage === 0 && user.text().indexOf("0.5") >= 0 && state.text().indexOf("list") >= 0) {
            stage = 1;
            const saved = JSON.parse(user.text());
            t.compare(saved.motion.speed, 0.5, "saved to settings.json");
            t.compare(saved.note, "kept", "a key the schema does not know is kept");
            t.compare(saved.shelf.pins.join(), "foot", "the user's own pins are kept under the managed ones");
            t.verify(managed.text().indexOf("kitty") < 0, "managed.json is never written");
            const st = JSON.parse(state.text());
            t.compare(st.launcher.view + "," + st.launcher.other, "list,1", "both state changes in state.json");
            // someone edits the files: the shell follows
            user.setText(JSON.stringify({ motion: { speed: 3 } }));
            managed.setText("{}");
        } else if (stage === 1 && Settings.value("motion.speed") === 3 && !Settings.isManaged("shelf.pins")) {
            stage = 2;
            t.compare(Settings.value("shelf.pins"), undefined, "nothing pins once neither file does");
            t.verify(Settings.reset("motion.speed"), "reset");
            t.compare(Settings.value("motion.speed"), 1, "back to the default");
        } else if (stage === 2 && user.text().trim() === "{}") {
            stage = 3;                      // the reset is on disk (writes are not in order otherwise)
            user.setText("{ oops");
        } else if (stage === 3 && user.text() === "{ oops") {
            stage = 4;
            settle.start();
        }
    }
    // a broken file is read in its own time; then changes are refused and the file is left alone
    Timer {
        id: settle
        interval: 500
        onTriggered: {
            t.compare(Settings.value("motion.speed"), 1, "the last good value stays");
            t.verify(!Settings.set("motion.speed", 2), "no changes while settings.json does not parse");
            t.compare(user.text(), "{ oops", "and it is not overwritten");
            t.done();
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (root.stage === 0) state.reload();
            root.check();
        }
    }
    Timer {
        interval: 10000
        running: true
        onTriggered: {
            t.verify(false, "timed out at stage " + root.stage);
            t.done();
        }
    }
}
