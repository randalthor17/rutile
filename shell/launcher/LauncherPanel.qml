pragma ComponentBehavior: Bound
// The launcher (plan 2.7): a search field over a grid of apps, ranked by Scorer.js as you type. Plain QtQuick on
// `apps` ([{id, name, icon (URL), genericName, keywords, subtitle}]), so it tests offscreen; LauncherWindow.qml
// gives it the desktop entries. The keyboard stays in the field: the arrows move through the grid (Home and End
// still move the text cursor), Enter opens the current app, Escape closes. It grows in and out with the shared popup motion (D43), then reports `hidden`.
import QtQuick
import qs.common
import qs.components
import "Scorer.js" as Scorer

Rectangle {
    id: root

    property var apps: []
    property alias query: field.text
    readonly property var results: Scorer.rank(apps, query)
    readonly property alias currentIndex: grid.currentIndex
    readonly property int columns: 5
    readonly property real cell: Spacing.xxxl * 2 + Spacing.sm
    property bool shown: true

    signal launched(var app)
    signal closeRequested()
    signal hidden()

    // Close when another window takes the keyboard, after having had it (as Quick Settings, D41).
    readonly property bool windowActive: Window.active
    property bool hadWindowFocus: false
    onWindowActiveChanged: {
        if (windowActive) hadWindowFocus = true;
        else if (hadWindowFocus) closeRequested();
    }

    function launchCurrent() {
        if (grid.currentIndex >= 0 && grid.currentIndex < results.length) launched(results[grid.currentIndex]);
    }

    implicitWidth: columns * cell + 2 * Spacing.lg
    implicitHeight: content.height + 2 * Spacing.lg
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.extraLarge
    color: Colors.surfaceContainer

    PopupMotion {
        target: root
        shown: root.shown
        origin: Item.Bottom
        onHidden: root.hidden()
    }

    Column {
        id: content
        x: Spacing.lg
        y: Spacing.lg
        width: parent.width - 2 * Spacing.lg
        spacing: Spacing.md

        Rectangle {
            width: parent.width
            height: Spacing.xxxl
            radius: height / 2
            color: Colors.surfaceContainerHigh

            Icon {
                id: searchIcon
                x: Spacing.md
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: Spacing.xl
                color: Colors.surfaceVariantOn
            }
            Text {
                anchors.left: field.left
                anchors.verticalCenter: parent.verticalCenter
                visible: field.text === ""
                text: "Search apps"
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodyLarge)
            }
            TextInput {
                id: field
                objectName: "launcherSearch"
                anchors.left: searchIcon.right
                anchors.leftMargin: Spacing.md
                anchors.right: parent.right
                anchors.rightMargin: Spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                color: Colors.surfaceOn
                selectionColor: Colors.primary
                selectedTextColor: Colors.primaryOn
                font: Type.font(Type.bodyLarge)
                Keys.onUpPressed: grid.moveCurrentIndexUp()
                Keys.onDownPressed: grid.moveCurrentIndexDown()
                Keys.onLeftPressed: grid.moveCurrentIndexLeft()
                Keys.onRightPressed: grid.moveCurrentIndexRight()
                Keys.onReturnPressed: root.launchCurrent()
                Keys.onEnterPressed: root.launchCurrent()
                Keys.onEscapePressed: root.closeRequested()
            }
        }

        GridView {
            id: grid
            objectName: "launcherGrid"
            width: parent.width
            height: 4 * root.cell
            cellWidth: root.cell
            cellHeight: root.cell
            clip: true
            model: root.results
            // a new result list starts at its best match: GridView resets currentIndex when the model changes
            keyNavigationWraps: false
            boundsBehavior: Flickable.StopAtBounds
            delegate: LauncherTile {
                required property var modelData
                required property int index
                objectName: "launcherApp_" + modelData.id
                width: root.cell
                height: root.cell
                name: modelData.name
                iconSource: modelData.icon || ""
                current: index === grid.currentIndex
                onClicked: root.launched(modelData)
            }

            Text {
                anchors.centerIn: parent
                visible: root.results.length === 0
                text: root.apps.length === 0 ? "No apps found" : "No apps match"
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodyLarge)
            }
        }
    }
}
