// The system source (plan 4.2, D79, D87): /proc, df of / and the processors' frequencies, read every second (`every`);
// processor use and the network's rates from two readings in a row, histories for charts kept here.
import QtQuick
import qs.widgethost
import Quickshell.Io
import "../Sources.js" as Sources

WidgetSource {
    id: root
    property var previous: null
    property real previousTime: 0
    property string cpuName: ""

    // the processor's name, once (/proc/cpuinfo is long; the name does not change)
    Process {
        running: true
        command: ["cat", "/proc/cpuinfo"]
        stdout: StdioCollector { onStreamFinished: root.cpuName = Sources.cpuName(text) }
    }

    Process {
        id: read
        command: ["sh", "-c", 'cat /proc/stat /proc/meminfo /proc/uptime /proc/loadavg /proc/net/dev; df -P -B1 / 2>/dev/null; ' +
                  'for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do [ -r "$f" ] && printf "freq %s\\n" "$(cat "$f")"; done; true']
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now();
                const sample = Sources.procSample(text);
                root.value = Sources.system(root.previous, sample, (now - root.previousTime) / 1000, root.value, root.options,
                                            root.cpuName);
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
