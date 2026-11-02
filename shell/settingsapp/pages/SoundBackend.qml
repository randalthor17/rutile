// The Sound page's backend (SoundPage.qml has the interface): PipeWire's audio devices through Quickshell, and the
// defaults' volume and mute through AudioService. The window loads it only while the page is open (D31). Choosing
// a device sets Quickshell's preferredDefaultAudioSink (or Source): a hint PipeWire follows when it can; the
// page shows the default actually in use.
import QtQuick
import Quickshell.Services.Pipewire
import qs.services

Item {
    id: root

    readonly property bool available: Pipewire.ready
    // devices, not apps' streams; a device without audio (video) is left out
    readonly property var devices: Pipewire.nodes.values.filter(n => n && n.audio && !n.isStream)
    readonly property var sinks: devices.filter(n => n.isSink)
    readonly property var sources: devices.filter(n => !n.isSink)
    readonly property var outputs: sinks.map(n => ({ id: n.id, name: label(n) }))
    readonly property var inputs: sources.map(n => ({ id: n.id, name: label(n) }))
    readonly property int output: AudioService.sink?.id ?? -1
    readonly property int input: AudioService.source?.id ?? -1
    readonly property real volume: AudioService.volume
    readonly property bool muted: AudioService.muted
    readonly property real inputVolume: AudioService.micVolume
    readonly property bool inputMuted: AudioService.micMuted

    function label(n) {
        return n.description || n.nickname || n.name;
    }
    function setOutput(id) {
        const n = sinks.find(x => x.id === id);
        if (n) Pipewire.preferredDefaultAudioSink = n;
    }
    function setInput(id) {
        const n = sources.find(x => x.id === id);
        if (n) Pipewire.preferredDefaultAudioSource = n;
    }
    function setVolume(v) { AudioService.setVolume(v); }
    function setMuted(m) { AudioService.setMuted(m); }
    function setInputVolume(v) { AudioService.setMicVolume(v); }
    function setInputMuted(m) { AudioService.setMicMuted(m); }
}
