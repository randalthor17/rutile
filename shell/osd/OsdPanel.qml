// The on-screen display for volume and brightness (plan 2.8): a pill holding the level as Quick Settings' slider,
// shown when a key (or anything else) changes the level and gone after `holdTime` unless the pointer is on it or
// the slider is held. Its slider can be dragged. show() opens it, or keeps it open, on a kind; it grows and fades
// with the shared popup motion from its bottom edge (D43), and `hidden` fires once it has closed, so the window
// around it (OsdWindow) can be unloaded.
import QtQuick
import qs.common
import qs.components

Surface {
    id: root

    property string kind: "volume"     // volume or brightness
    property real value: 0             // 0..1
    property bool muted: false         // volume only: the slider shows 0 and the muted icon
    property int holdTime: 1500        // ms on screen after the last change
    property bool open: false

    readonly property alias slider: levelSlider
    readonly property bool held: hover.hovered || levelSlider.pressed
    readonly property string iconName: kind === "brightness" ? "brightness_medium"
                                     : muted ? "music_off" : "music_note"

    signal moved(string kind, real value)
    signal hidden()

    function show(newKind) {
        kind = newKind;
        open = true;
        hold.restart();
    }

    implicitWidth: 240 + 2 * Spacing.md
    implicitHeight: slider.implicitHeight + 2 * Spacing.sm
    radius: Shapes.full
    tone: Colors.surfaceContainer

    PopupMotion {
        target: root
        shown: root.open
        origin: Item.Bottom
        onHidden: root.hidden()
    }

    Timer {
        id: hold
        interval: root.holdTime
        onTriggered: if (!root.held) root.open = false
    }
    // Let go: the hold starts again from here.
    onHeldChanged: if (!held && open) hold.restart()

    HoverHandler { id: hover }

    Slider {
        id: levelSlider
        objectName: "osdSlider"
        anchors.fill: parent
        anchors.leftMargin: Spacing.md
        anchors.rightMargin: Spacing.md
        anchors.topMargin: Spacing.sm
        anchors.bottomMargin: Spacing.sm
        size: "m"
        endIcon: root.iconName
        onMoved: v => {
            hold.restart();
            root.moved(root.kind, v);
        }
        Binding on value {
            value: root.muted && root.kind === "volume" ? 0 : root.value
            when: !levelSlider.pressed
            restoreMode: Binding.RestoreNone
        }
    }
}
