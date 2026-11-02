// The Bluetooth page's backend (plan 5.2) against the system's real BlueZ, read only and without discovering
// (`scan: false`): each device once, named, paired ones first; nothing connected, paired or switched. Without an
// adapter it logs a skip.
import QtQuick
import Quickshell
import qs.services      // as the shell has it: Quickshell makes the qs modules something imports

ShellRoot {
    id: root
    QsTest { id: t }
    Loader { id: backend }
    Component.onCompleted: backend.setSource(Qt.resolvedUrl("settingsapp/pages/BluetoothBackend.qml"), { scan: false })
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            const b = backend.item;
            t.verify(b !== null, "it loads: " + backend.status);
            if (!b || !b.available) {
                console.log("QSTEST SKIPPED: no Bluetooth adapter");
                t.done();
                return;
            }
            const d = b.devices;
            t.compare(new Set(d.map(x => x.id)).size, d.length, "each device once");
            for (let i = 0; i < d.length; i++) {
                t.verify(d[i].name !== "" && /^[0-9A-F:]{17}$/.test(d[i].id), "a name and an address: " + JSON.stringify(d[i]));
                if (i > 0) t.verify(d[i - 1].paired || !d[i].paired, "paired first");
                t.verify(d[i].battery === -1 || (d[i].battery >= 0 && d[i].battery <= 1), "a battery level or none");
            }
            console.log("QSTEST note: " + d.length + " devices, adapter " + (b.enabled ? "on" : "off"));
            t.done();
        }
    }
}
