pragma Singleton
// The shell's settings and state (D45). Settings come from $XDG_CONFIG_HOME/rutile/settings.json (the user's,
// written here) and managed.json (home-manager's, never written here), checked against settings/schema.json;
// a managed key wins and cannot be changed. State is what the shell remembers between runs (the launcher's
// view), in $XDG_STATE_HOME/rutile/state.json. Both settings files are watched, so an edit or a home-manager
// switch applies at once. A file that does not parse is never overwritten: the last good values stay, and
// changes are refused until it is fixed.
//
// Bind to `Settings.value("motion.speed")`: it reads `values`, so the binding follows changes.
import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsSchema.js" as Schema
import "SettingsStore.js" as Store

Singleton {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/rutile"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rutile"

    // {key: value} for every setting in the schema, and {key: true} for those set in Nix
    property var values: Store.resolve(Schema.schema, {}, {}).values
    property var managed: ({})

    // the files' objects; null while a file does not parse
    property var userData: ({})
    property var managedData: ({})
    property var stateData: ({})

    function value(key) {
        return root.values[key];
    }
    function isManaged(key) {
        return !!root.managed[key];
    }

    // Saves `value` for `key` in settings.json; false (and nothing changes) for an unknown or managed key, a value
    // the schema does not allow, or a settings.json that does not parse.
    function set(key, value) {
        const leaf = Store.leaves(Schema.schema)[key];
        if (!leaf || isManaged(key) || userData === null || (value !== undefined && !Store.valid(leaf, value))) {
            console.warn("rutile: cannot set " + key + " to " + JSON.stringify(value));
            return false;
        }
        userData = Store.withValue(userData, key, value);
        userFile.setText(Store.format(userData));
        resolve();
        return true;
    }
    // Back to the default (or to what Nix set).
    function reset(key) {
        return set(key, undefined);
    }

    function stateValue(key, fallback) {
        const v = Store.get(stateData ?? {}, key);
        return v === undefined ? fallback : v;
    }
    // Remembers `value` for `key`; writes happen once per event loop turn, however many keys change.
    function setState(key, value) {
        if (stateData === null) return;             // state.json does not parse: keep it for the user to look at
        if (JSON.stringify(Store.get(stateData, key)) === JSON.stringify(value)) return;   // no write, no loop
        stateData = Store.withValue(stateData, key, value);
        Qt.callLater(writeState);
    }
    function writeState() {
        stateFile.setText(Store.format(stateData));
    }

    function resolve() {
        const r = Store.resolve(Schema.schema, userData ?? {}, managedData ?? {});
        r.problems.forEach(p => console.warn("rutile: " + root.configDir + "/" + p));
        values = r.values;
        managed = r.managed;
    }

    // Reads a FileView into `prop` after a load (`error` undefined) or a failed one: {} for a missing file, null
    // (and a warning) for one that cannot be read or does not parse, so nothing is written over it.
    function load(view, prop, error) {
        if (error === FileViewError.FileNotFound) {
            root[prop] = {};
            return;
        }
        const r = error !== undefined ? { error: FileViewError.toString(error) } : Store.parse(view.text());
        if (r.error !== undefined) console.warn("rutile: cannot read " + view.path + ": " + r.error);
        root[prop] = r.error !== undefined ? null : r.data;
    }

    FileView {
        id: userFile
        path: root.configDir + "/settings.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.load(userFile, "userData"); root.resolve(); }
        onLoadFailed: error => {
            root.load(userFile, "userData", error);
            root.resolve();
        }
        onSaveFailed: error => console.warn("rutile: cannot save " + path + ": " + FileViewError.toString(error))
    }
    FileView {
        id: managedFile
        path: root.configDir + "/managed.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.load(managedFile, "managedData"); root.resolve(); }
        onLoadFailed: error => {
            root.load(managedFile, "managedData", error);
            root.resolve();
        }
    }
    FileView {
        id: stateFile
        path: root.stateDir + "/state.json"
        blockLoading: true
        printErrors: false
        onLoaded: root.load(stateFile, "stateData")
        onLoadFailed: error => {
            root.load(stateFile, "stateData", error);
        }
        onSaveFailed: error => console.warn("rutile: cannot save " + path + ": " + FileViewError.toString(error))
    }

    // The settings are there on the first frame: blockLoading makes text() wait for the first read. A file that
    // is missing or cannot be read gives "" and is left to onLoadFailed (`loaded` is not the test: it was true
    // after a failed read in a probe).
    function loadFirst(view, prop) {
        if (view.text() !== "") load(view, prop);
    }
    Component.onCompleted: {
        loadFirst(userFile, "userData");
        loadFirst(managedFile, "managedData");
        loadFirst(stateFile, "stateData");
        resolve();
    }
}
