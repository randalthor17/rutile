pragma ComponentBehavior: Bound
// One widget on the desktop grid (plan 4.4, D81): its spec (from `specs`, by the item's path) drawn by WidgetHost
// with its own data sources. The grid sets its size in cells; the widget sits at the top of them, and one taller
// than that is scaled down to fit, never up, so all of it shows. While editing, an outline shows its cells. A file that cannot be read shows nothing, except while editing: then a card names
// it, so it can be found and removed.
import QtQuick
import qs.common
import qs.widgethost

Item {
    id: root

    property var modelData: ({})
    property var specs: ({})
    property bool editMode: false
    readonly property var spec: specs[modelData.path ?? ""] ?? null
    readonly property alias host: widgetHost
    readonly property real fit: widgetHost.implicitHeight > height && widgetHost.implicitHeight > 0 ? height / widgetHost.implicitHeight : 1

    objectName: "desktopWidget_" + (modelData.id ?? "")

    Rectangle {
        anchors.fill: parent
        visible: root.editMode
        radius: Shapes.extraLarge
        color: "transparent"
        border.color: Colors.outlineVariant
        border.width: Spacing.xs / 2
    }
    WidgetSources {
        id: sources
        spec: root.spec
    }
    WidgetHost {
        id: widgetHost
        objectName: "desktopWidgetHost"
        width: root.width
        x: (root.width - width * scale) / 2
        transformOrigin: Item.TopLeft
        scale: root.fit
        spec: root.spec
        values: sources.values
    }

    Loader {
        objectName: "desktopWidgetMissing"
        anchors.fill: parent
        active: root.editMode && !widgetHost.readable
        sourceComponent: Rectangle {
            radius: Shapes.extraLarge
            color: Colors.errorContainer
            Text {
                anchors.fill: parent
                anchors.margins: Spacing.lg
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: "Cannot show " + String(root.modelData.path ?? "").replace(/^.*\//, "")
                color: Colors.errorContainerOn
                font: Type.font(Type.bodyMedium)
            }
        }
    }
}
