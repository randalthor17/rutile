// What is playing (D117): a card in Quick Settings for an MPRIS player (Quickshell's MprisPlayer, or a fake with the
// same members): the cover, the title and artist, previous, play or pause, next, and how far along it is (dragged to
// seek where the player allows). With several players, the player's name switches to the next one. Plain QtQuick,
// so it tests offscreen. MPRIS does not report the position as it moves, so the card asks for it each second while
// it plays (`positionChanged()`, as Quickshell's docs say).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import "Media.js" as Media

Rectangle {
    id: root

    property var player: null
    property int playerCount: 1
    signal switchRequested()        // the player's name was clicked, with more than one player

    readonly property bool timed: !!player && player.lengthSupported && player.length > 0
    readonly property bool seekable: timed && player.canSeek && player.positionSupported

    implicitHeight: column.height + 2 * Spacing.md
    height: implicitHeight
    radius: Shapes.extraLarge
    color: Colors.surfaceContainerHigh

    Timer {
        interval: 1000
        repeat: true
        running: root.visible && !!root.player && root.player.isPlaying && root.timed
        onTriggered: root.player.positionChanged()
    }

    Column {
        id: column
        x: Spacing.md
        y: Spacing.md
        width: parent.width - 2 * Spacing.md
        spacing: Spacing.sm

        Row {
            width: parent.width
            spacing: Spacing.md

            Rectangle {
                id: cover
                objectName: "mediaCover"
                width: Spacing.xxxl + Spacing.md
                height: width
                radius: Shapes.medium
                color: Colors.secondaryContainer
                Icon {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    name: "music_note"
                    size: Spacing.xl
                    color: Colors.secondaryContainerOn
                }
                Image {
                    id: art
                    objectName: "mediaArt"
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: root.player?.trackArtUrl ?? ""
                    sourceSize.width: width
                    sourceSize.height: height
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Column {
                width: parent.width - cover.width - controls.width - 2 * parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Spacing.xs / 2
                Text {
                    objectName: "mediaTitle"
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player?.trackTitle || root.player?.identity || ""
                    color: Colors.surfaceOn
                    font: Type.font(Type.titleSmall)
                }
                Text {
                    objectName: "mediaArtist"
                    width: parent.width
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: root.player?.trackArtist ?? ""
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.bodyMedium)
                }
                Text {
                    id: playerName
                    objectName: "mediaPlayer"
                    width: Math.min(implicitWidth, parent.width)
                    elide: Text.ElideRight
                    text: (root.player?.identity ?? "") + (root.playerCount > 1 ? "  ›" : "")
                    color: root.playerCount > 1 ? Colors.primary : Colors.surfaceVariantOn
                    font: Type.font(Type.labelMedium)
                    MouseArea {
                        objectName: "mediaSwitch"
                        anchors.fill: parent
                        anchors.margins: -Spacing.xs
                        enabled: root.playerCount > 1
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.switchRequested()
                    }
                }
            }

            Row {
                id: controls
                anchors.verticalCenter: parent.verticalCenter
                spacing: Spacing.xs
                IconButton {
                    objectName: "mediaPrevious"
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "skip_previous"
                    enabled: !!root.player && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                IconButton {
                    objectName: "mediaPlayPause"
                    anchors.verticalCenter: parent.verticalCenter
                    type: "filled"
                    iconName: root.player?.isPlaying ? "pause" : "play_arrow"
                    enabled: !!root.player && root.player.canTogglePlaying
                    onClicked: root.player.togglePlaying()
                }
                IconButton {
                    objectName: "mediaNext"
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "skip_next"
                    enabled: !!root.player && root.player.canGoNext
                    onClicked: root.player.next()
                }
            }
        }

        Row {
            visible: root.timed
            width: parent.width
            spacing: Spacing.sm
            Text {
                objectName: "mediaPosition"
                anchors.verticalCenter: parent.verticalCenter
                text: Media.time(root.player?.position ?? 0)
                color: Colors.surfaceVariantOn
                font: Type.font(Type.labelSmall)
            }
            Slider {
                id: progress
                objectName: "mediaProgress"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 2 * (lengthText.implicitWidth + parent.spacing)
                ticks: false
                enabled: root.seekable
                onMoved: v => root.player.position = v * root.player.length
                Binding on value {
                    value: root.timed ? Math.min(1, (root.player?.position ?? 0) / root.player.length) : 0
                    when: !progress.pressed
                    restoreMode: Binding.RestoreNone
                }
            }
            Text {
                id: lengthText
                objectName: "mediaLength"
                anchors.verticalCenter: parent.verticalCenter
                text: Media.time(root.player?.length ?? 0)
                color: Colors.surfaceVariantOn
                font: Type.font(Type.labelSmall)
            }
        }
    }
}
