// The Sound page's backend (plan 5.2) against the session's real PipeWire, read only: it lists devices, not
// apps' streams, each once with a name, and the defaults in use are among them. Nothing is changed (no default,
// no volume). Without PipeWire (no session) it logs a skip.
import QtQuick
import Quickshell
import qs.services      // as the shell has it: Quickshell makes the qs modules something imports

ShellRoot {
    id: root
    QsTest { id: t }
    Loader {
        id: backend
        source: Qt.resolvedUrl("settingsapp/pages/SoundBackend.qml")
    }
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            const b = backend.item;
            t.verify(b !== null, "it loads: " + backend.status);
            if (!b || !b.available) {
                console.log("QSTEST SKIPPED: no PipeWire session");
                t.done();
                return;
            }
            const all = b.outputs.concat(b.inputs);
            t.verify(b.outputs.length > 0, "an output: " + JSON.stringify(b.outputs));
            t.compare(new Set(all.map(d => d.id)).size, all.length, "each device once");
            for (const d of all)
                t.verify(typeof d.name === "string" && d.name !== "", "a name: " + JSON.stringify(d));
            t.verify(b.sinks.every(n => n.isSink && !n.isStream && n.audio), "outputs are devices with audio");
            t.verify(b.sources.every(n => !n.isSink && !n.isStream && n.audio), "inputs too");
            if (b.output >= 0)
                t.verify(b.outputs.some(d => d.id === b.output), "the default output is listed");
            if (b.input >= 0)
                t.verify(b.inputs.some(d => d.id === b.input), "the default input is listed");
            t.verify(b.volume >= 0 && b.volume <= 1.5, "a volume: " + b.volume);
            t.done();
        }
    }
}
