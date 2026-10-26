// The default output and input through Quickshell's Pipewire service. Volume and mute are only valid
// on bound nodes, so the tracker binds both defaults (and follows them when the defaults change).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property bool available: !!sink && !!sink.audio
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool micAvailable: !!source && !!source.audio
    readonly property bool micMuted: source?.audio?.muted ?? false

    function setVolume(v) {
        if (!available) return;
        sink.audio.volume = Math.max(0, Math.min(1, v));
        if (v > 0 && sink.audio.muted) sink.audio.muted = false;
    }

    function setMuted(m) {
        if (available) sink.audio.muted = m;
    }

    function setMicMuted(m) {
        if (micAvailable) source.audio.muted = m;
    }

    PwObjectTracker {
        objects: [root.sink, root.source]
    }
}
