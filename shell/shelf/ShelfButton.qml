// One app or window on the shelf: its icon (or its initial on a tonal circle when the icon theme has none), a state
// layer, a press that shrinks it on the spatial spring, and a mark under it: a dot for `running`, a longer primary
// dash for `active` (the shelf marks the focused window).
import QtQuick
import qs.common
import qs.components

Item {
    id: root

    property string name: ""
    property string iconSource: ""      // an image URL (Quickshell.iconPath in the shell), or "" for the fallback
    property bool running: false
    property bool active: false

    signal clicked()

    implicitWidth: Spacing.xxxl
    implicitHeight: Spacing.xxxl
    width: implicitWidth
    height: implicitHeight

    Item {
        id: face
        anchors.fill: parent
        scale: 1 - 0.1 * pressSpring.value      // M3E press: shrink a little, spring back
        Spring {
            id: pressSpring
            target: stateLayer.pressed ? 1 : 0
            stiffness: Motion.spring("spatial", "fast").stiffness
            dampingRatio: Motion.spring("spatial", "fast").dampingRatio
        }

        Image {
            objectName: "shelfIcon"
            anchors.centerIn: parent
            visible: root.iconSource !== "" && status === Image.Ready
            source: root.iconSource
            width: Spacing.xxl + Spacing.sm
            height: width
            sourceSize.width: width
            sourceSize.height: height
            asynchronous: true
        }
        Rectangle {
            objectName: "shelfFallbackIcon"
            anchors.centerIn: parent
            visible: root.iconSource === ""
            width: Spacing.xxl + Spacing.sm
            height: width
            radius: width / 2
            color: Colors.secondaryContainer
            Text {
                anchors.centerIn: parent
                text: root.name.charAt(0).toUpperCase()
                color: Colors.secondaryContainerOn
                font: Type.font(Type.titleMedium)
            }
        }
        StateLayer {
            id: stateLayer
            anchors.fill: parent
            radius: width / 2
            stateColor: Colors.surfaceOn
            onClicked: root.clicked()
        }
    }

    Rectangle {
        objectName: "shelfRunningMark"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        visible: root.running
        width: root.active ? Spacing.lg : Spacing.xs
        height: Spacing.xs / 2
        radius: height / 2
        color: root.active ? Colors.primary : Colors.surfaceVariantOn
        Behavior on width { EffectsNumber {} }
        Behavior on color { EffectsColor {} }
    }

    Accessible.role: Accessible.Button
    Accessible.name: name
}
