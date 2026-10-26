pragma ComponentBehavior: Bound
// One app in the launcher: its icon (or its initial on a tonal circle when the icon theme has none), a state
// layer, and a tonal background while it is the keyboard's current item. A right click asks for its menu. As a grid tile the name sits under the
// icon; as a list row (`row`) a smaller icon leads and the name has the description under it.
import QtQuick
import qs.common
import qs.components

Item {
    id: root

    property string name: ""
    property string subtitle: ""
    property string iconSource: ""
    property bool current: false
    property bool row: false

    signal clicked()
    signal menuRequested()

    Rectangle {
        objectName: "launcherTileCurrent"
        anchors.fill: parent
        anchors.margins: Spacing.xs
        radius: Shapes.large
        color: Colors.secondaryContainer
        opacity: root.current ? 1 : 0
        Behavior on opacity { EffectsNumber { speed: "fast" } }
    }

    Item {
        id: icon
        readonly property real gridTop: (root.height - height - Spacing.sm - nameText.height) / 2
        x: root.row ? Spacing.lg : (root.width - width) / 2
        y: root.row ? (root.height - height) / 2 : gridTop
        width: root.row ? Spacing.xxl : Spacing.xxxl
        height: width
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
                font: Type.font(root.row ? Type.titleMedium : Type.titleLarge)
            }
        }
    }

    Column {
        id: label
        x: root.row ? icon.x + icon.width + Spacing.lg : Spacing.sm
        y: root.row ? (root.height - height) / 2 : icon.y + icon.height + Spacing.sm
        width: root.row ? root.width - x - Spacing.lg : root.width - 2 * Spacing.sm

        Text {
            id: nameText
            width: parent.width
            text: root.name
            horizontalAlignment: root.row ? Text.AlignLeft : Text.AlignHCenter
            wrapMode: root.row ? Text.NoWrap : Text.Wrap
            maximumLineCount: root.row ? 1 : 2
            elide: Text.ElideRight
            color: root.current ? Colors.secondaryContainerOn : Colors.surfaceOn
            font: Type.font(root.row ? Type.bodyLarge : Type.labelMedium)
        }
        // only list rows have one (memory: a grid holds a few dozen tiles)
        Loader {
            width: parent.width
            active: root.row && root.subtitle !== ""
            sourceComponent: Text {
                objectName: "launcherTileSubtitle"
                text: root.subtitle
                elide: Text.ElideRight
                color: root.current ? Colors.secondaryContainerOn : Colors.surfaceVariantOn
                font: Type.font(Type.bodyMedium)
            }
        }
    }

    StateLayer {
        anchors.fill: parent
        anchors.margins: Spacing.xs
        radius: Shapes.large
        stateColor: Colors.surfaceOn
        onClicked: root.clicked()
    }
    // right clicks only: left presses go through to the state layer
    MouseArea {
        objectName: "launcherTileMenuArea"
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.menuRequested()
    }

    Accessible.role: Accessible.Button
    Accessible.name: name
}
