// The system source (plan 4.2, D79): /proc read every 2 seconds; processor use from two readings in a row.
import QtQuick
import qs.widgethost
import Quickshell.Io
import "../Sources.js" as Sources

WidgetSource {
    id: root
    property var previous: null

    Process {
        id: read
        command: ["cat", "/proc/stat", "/proc/meminfo", "/proc/uptime", "/proc/loadavg"]
        stdout: StdioCollector {
            onStreamFinished: {
                const sample = Sources.procSample(text);
                root.value = Sources.system(root.previous, sample);
                root.previous = sample;
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: read.running = true
    }
}
