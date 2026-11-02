// The Network page's backend (plan 5.2) against the system's real NetworkManager, read only and without scanning
// (`scan: false`): each network once by name, the connected one first, then by signal; wired devices named;
// nothing connected, forgotten or switched. Without NetworkManager it logs a skip.
import QtQuick
import Quickshell
import qs.services      // as the shell has it: Quickshell makes the qs modules something imports

ShellRoot {
    id: root
    QsTest { id: t }
    Loader { id: backend }
    Component.onCompleted: backend.setSource(Qt.resolvedUrl("settingsapp/pages/NetworkBackend.qml"), { scan: false })
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            const b = backend.item;
            t.verify(b !== null, "it loads: " + backend.status);
            if (!b || !b.available) {
                console.log("QSTEST SKIPPED: no NetworkManager devices");
                t.done();
                return;
            }
            const n = b.networks;
            t.compare(new Set(n.map(x => x.id)).size, n.length, "each network once");
            for (let i = 0; i < n.length; i++) {
                t.verify(n[i].name !== "" && n[i].signal >= 0 && n[i].signal <= 1, "a name and a signal: " + JSON.stringify(n[i]));
                if (i > 0 && !n[i - 1].connected)
                    t.verify(!n[i].connected && n[i - 1].signal >= n[i].signal, "sorted: " + JSON.stringify(n.slice(i - 1, i + 1)));
            }
            t.verify(n.filter(x => x.connected).length <= 1, "one connected");
            for (const w of b.wired)
                t.verify(typeof w.name === "string" && w.name !== "", "a wired device's name");
            t.compare(b.asking, "", "asks nothing by itself");
            console.log("QSTEST note: " + n.length + " networks, " + b.wired.length + " wired");
            t.done();
        }
    }
}
