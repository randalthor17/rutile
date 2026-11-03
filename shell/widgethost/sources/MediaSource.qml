// The media source (plan 4.2, D79): the MPRIS player that is playing, else the first. Its position is read
// again every second while it plays and `progress` is bound (MPRIS sends no position updates).
import QtQuick
import qs.widgethost
import Quickshell.Services.Mpris
import "../Sources.js" as Sources

WidgetSource {
    id: root
    readonly property var players: Mpris.players.values
    readonly property var player: {
        for (const p of players) if (p.isPlaying) return p;
        return players.length ? players[0] : null;
    }
    property real position: player ? player.position : 0
    value: Sources.media(player ? {
        name: player.identity, playing: player.isPlaying, title: player.trackTitle, artist: player.trackArtist,
        album: player.trackAlbum, art: player.trackArtUrl, position: position, length: player.length
    } : null)
    Timer {
        interval: 1000
        repeat: true
        running: !!root.player && root.player.isPlaying && root.fields.indexOf("progress") >= 0
        onTriggered: root.position = root.player.position
    }
}
