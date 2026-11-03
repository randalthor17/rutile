// The sensors source (D87): every hwmon temperature, the processor's found by its driver (k10temp, coretemp, ...),
// and the processor's power from RAPL's energy counter when this user may read it, every second (`every`).
import QtQuick
import qs.widgethost
import Quickshell.Io
import "../Sources.js" as Sources

WidgetSource {
    id: root
    property var previous: null
    property real previousTime: 0

    Process {
        id: read
        command: ["sh", "-c", 'for h in /sys/class/hwmon/hwmon*; do echo "hwmon $(cat "$h/name" 2>/dev/null)"; ' +
                  'for f in "$h"/temp*_input; do [ -r "$f" ] && echo "${f##*/} $(cat "$f" 2>/dev/null) $(cat "${f%_*}_label" 2>/dev/null)"; done; done; ' +
                  'e=/sys/class/powercap/intel-rapl:0/energy_uj; [ -r "$e" ] && echo "rapl $(cat "$e" 2>/dev/null)"; true']
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now();
                const sample = Sources.sensorsSample(text);
                root.value = Sources.sensors(root.previous, sample, (now - root.previousTime) / 1000, root.value, root.options);
                root.previous = sample;
                root.previousTime = now;
            }
        }
    }
    Timer {
        interval: Sources.pollInterval(root.options)
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: read.running = true
    }
}
