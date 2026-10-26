// One app in the launcher's grid: its icon (or its initial on a tonal circle when the icon theme has none) and
// its name under it, a state layer, and a tonal background while it is the keyboard's current item.
import QtQuick
import qs.common
import qs.components

Item {
    id: root

    property string name: ""
    property string iconSource: ""
    property bool current: false

    signal clicked()

    Rectangle {
        objectName: "launcherTileCurrent"
        anchors.fill: parent
        anchors.margins: Spacing.xs
        radius: Shapes.large
        color: Colors.secondaryContainer
        opacity: root.current ? 1 : 0
        Behavior on opacity { EffectsNumber { speed: "fast" } }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Spacing.sm
        spacing: Spacing.sm

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Spacing.xxxl
            height: Spacing.xxxl
            Image {
                anchors.fill: parent
                visible: root.iconSource !== "" && status === Image.Ready
                source: root.iconSource
                sourceSize.width: width
                sourceSize.height: height
                asynchronous: true
            }
            Rectangle {
                objectName: "launcherTileFallback"
                anchors.fill: parent
                visible: root.iconSource === ""
                radius: width / 2
                color: Colors.secondaryContainer
                Text {
                    anchors.centerIn: parent
                    text: root.name.charAt(0).toUpperCase()
                    color: Colors.secondaryContainerOn
                    font: Type.font(Type.titleLarge)
                }
            }
        }
        Text {
            width: parent.width
            text: root.name
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: root.current ? Colors.secondaryContainerOn : Colors.surfaceOn
            font: Type.font(Type.labelMedium)
        }
    }

    StateLayer {
        anchors.fill: parent
        anchors.margins: Spacing.xs
        radius: Shapes.large
        stateColor: Colors.surfaceOn
        onClicked: root.clicked()
    }

    Accessible.role: Accessible.Button
    Accessible.name: name
}
