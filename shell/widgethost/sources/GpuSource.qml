// The gpu source (D87): every graphics card, read every second (`every`): amdgpu's sysfs (use, video memory, the
// starred clock), i915's and xe's clock, each card's hwmon (temperatures, power or an energy counter, fan: amdgpu,
// nouveau, Intel's discrete cards), and nvidia-smi's numbers when NVIDIA's driver is installed. What a driver does
// not give is missing (i915 and xe report no use). The widget shows the card its `card` option names (card1), else
// the one with the most video memory. Names, read once: amdgpu.ids (libdrm) for AMD, pci.ids (hwdata) for the rest,
// nvidia-smi's own; RUTILE_AMDGPU_IDS and RUTILE_PCI_IDS point at them (the package sets both), else the usual
// system places.
import QtQuick
import qs.widgethost
import Quickshell
import Quickshell.Io
import "../Sources.js" as Sources

WidgetSource {
    id: root
    value: ({ available: false })
    property var previous: null
    property real previousTime: 0
    property var names: ({})
    readonly property string amdIds: Quickshell.env("RUTILE_AMDGPU_IDS") || "/usr/share/libdrm/amdgpu.ids"
    readonly property string pciIds: Quickshell.env("RUTILE_PCI_IDS") || ""

    Process {
        running: true
        command: ["sh", "-c", 'amd=$1 pci=$2; ' +
                  '[ -n "$pci" ] || for p in /usr/share/hwdata/pci.ids /usr/share/misc/pci.ids /usr/share/pci.ids; do [ -r "$p" ] && { pci=$p; break; }; done; ' +
                  'for c in /sys/class/drm/card[0-9] /sys/class/drm/card[0-9][0-9]; do d=$c/device; [ -r "$d/vendor" ] || continue; ' +
                  'v=$(cat "$d/vendor"); v=${v#0x}; dev=$(cat "$d/device" 2>/dev/null); dev=${dev#0x}; rev=$(cat "$d/revision" 2>/dev/null); rev=${rev#0x}; name=; ' +
                  'if [ "$v" = 1002 ] && [ -r "$amd" ]; then D=$(printf %s "$dev" | tr a-f A-F); R=$(printf %s "$rev" | tr a-f A-F); ' +
                  'name=$(sed -n "s/^$D,[[:space:]]*$R,[[:space:]]*//p" "$amd" | head -n 1); ' +
                  '[ -n "$name" ] || name=$(sed -n "s/^$D,[[:space:]]*[0-9A-F]*,[[:space:]]*//p" "$amd" | head -n 1); fi; ' +
                  'if [ -z "$name" ] && [ -n "$pci" ] && [ -r "$pci" ]; then name=$(sed -n "/^$v /,/^[0-9a-f]/{s/^\t$dev  //p}" "$pci" | head -n 1); ' +
                  '[ -n "$name" ] && name="pci $name"; fi; echo "name ${c##*/} $v:$dev $name"; done; true',
                  "sh", root.amdIds, root.pciIds]
        stdout: StdioCollector { onStreamFinished: root.names = Sources.gpuNames(text) }
    }
    Process {
        id: read
        command: ["sh", "-c", 'for c in /sys/class/drm/card[0-9] /sys/class/drm/card[0-9][0-9]; do d=$c/device; ' +
                  '[ -r "$d/vendor" ] || continue; echo "card ${c##*/}"; echo "vendor $(cat "$d/vendor")"; ' +
                  'sed -n "s/^DRIVER=/driver /p" "$d/uevent" 2>/dev/null; ' +
                  'for f in gpu_busy_percent mem_info_vram_total mem_info_vram_used; do [ -r "$d/$f" ] && echo "$f $(cat "$d/$f")"; done; ' +
                  '[ -r "$d/pp_dpm_sclk" ] && sed -n "/\\*/s/^/sclk /p" "$d/pp_dpm_sclk"; ' +
                  '[ -r "$c/gt_cur_freq_mhz" ] && echo "gtfreq $(cat "$c/gt_cur_freq_mhz")"; ' +
                  'for f in "$d"/tile0/gt0/freq0/cur_freq; do [ -r "$f" ] && echo "gtfreq $(cat "$f")"; done; ' +
                  'for h in "$d"/hwmon/hwmon*; do for f in "$h"/temp*_input "$h"/power1_average "$h"/power1_input "$h"/energy1_input "$h"/fan1_input; do ' +
                  '[ -r "$f" ] && echo "${f##*/} $(cat "$f" 2>/dev/null) $(cat "${f%_*}_label" 2>/dev/null)"; done; done; done; ' +
                  'command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,' +
                  'temperature.gpu,power.draw,fan.speed,clocks.gr,name --format=csv,noheader,nounits | sed "s/^/nvidia /"; true']
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now();
                const cards = Sources.gpuSample(text);
                root.value = Sources.gpu(cards, root.options, root.value, root.previous, (now - root.previousTime) / 1000, root.names);
                root.previous = cards;
                root.previousTime = now;
                root.error = root.value.available ? "" : (root.options.card ? "no card " + root.options.card : "no graphics card found");
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
