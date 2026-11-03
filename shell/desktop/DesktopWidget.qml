pragma ComponentBehavior: Bound
// One widget on the desktop grid (plan 4.4, D81): its spec (from `specs`, by the item's path) drawn by WidgetHost
// with its own data sources, in the cells the grid gives it (D84):
// - with `scaleText`, its text and icons scale with its size against `base`, a new widget's (0.8 to 2 times);
// - a widget that stretches (a card or tile, D83) fills the cells; one that cannot is centered in them;
// - one without a card or tile at its root is bare text on the wallpaper, so it keeps a margin from the edges;
// - one still taller than its cells is scaled down to fit, never up, so all of it shows.
// While editing, an outline shows its cells. A file that cannot be read shows nothing, except while editing: then a
// card names it, so it can be found and removed.
import QtQuick
import qs.common
import qs.widgethost

Item {
    id: root

    property var modelData: ({})
    property var specs: ({})
    property bool editMode: false
    property size base: Qt.size(width, height)             // the size of a new widget's cells
    property bool scaleText: false                         // widgets.scaleText, off by default
    readonly property var spec: specs[modelData.path ?? ""] ?? null
    readonly property alias host: widgetHost
    readonly property real textScale: !scaleText ? 1 : Math.max(0.8, Math.min(2, Math.min(width / Math.max(1, base.width),
                                                                          height / Math.max(1, base.height))))
    readonly property real inset: widgetHost.bare ? Spacing.lg : 0
    readonly property real room: height - 2 * inset
    readonly property real fit: widgetHost.implicitHeight > room && widgetHost.implicitHeight > 0 ? room / widgetHost.implicitHeight : 1

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
        width: root.width - 2 * root.inset
        height: root.fit < 1 || !stretches ? implicitHeight : root.room
        x: (root.width - width * scale) / 2
        y: root.inset + (root.room - height * scale) / 2
        textScale: root.textScale
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
