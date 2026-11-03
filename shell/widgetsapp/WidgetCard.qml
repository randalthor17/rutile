// One widget in the Widgets app (plan 4.5, D82): drawn live with its own data sources, its name, and what can be
// done with it: a template is used (copied to the user's folder, put on the desktop, opened to edit); one of the
// user's own is edited or put on the desktop. A widget that reads a web address says which, and whether Settings
// allows it yet (using a template allows it).
import QtQuick
import qs.common
import qs.components
import qs.widgethost
import "Gallery.js" as Gallery
import "../widgethost/Sources.js" as Sources

Rectangle {
    id: root

    property var entry: ({})                // {path, name}
    property var spec: null
    property bool mine: false
    property var allow: []                  // widgets.httpAllow
    readonly property string fetches: Gallery.fetches(spec)
    readonly property bool fetchAllowed: Sources.allowed(Gallery.url(spec), allow)
    readonly property alias host: widgetHost

    signal used()
    signal edited()
    signal placed()

    implicitHeight: column.implicitHeight + 2 * Spacing.lg
    radius: Shapes.extraLarge
    // an outline, not a fill: the widget's own surfaces show as they would on the desktop
    color: "transparent"
    border.color: Colors.outlineVariant
    border.width: 1

    WidgetSources {
        id: sources
        spec: root.spec
    }

    Column {
        id: column
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - 2 * Spacing.lg
        spacing: Spacing.md

        WidgetHost {
            id: widgetHost
            objectName: "galleryWidget"
            width: parent.width
            spec: root.spec
            values: sources.values
        }
        Text {
            width: parent.width
            text: root.spec?.name ?? root.entry.name ?? ""
            elide: Text.ElideRight
            color: Colors.surfaceOn
            font: Type.font(Type.titleMedium)
        }
        Text {
            objectName: "galleryFetches"
            width: parent.width
            visible: root.fetches !== ""
            wrapMode: Text.Wrap
            text: root.fetchAllowed ? "Reads " + root.fetches
                                    : "Reads " + root.fetches + (root.mine ? ", which Settings > Widgets does not allow yet"
                                                                          : "; using it allows that in Settings > Widgets")
            color: Colors.surfaceVariantOn
            font: Type.font(Type.bodySmall)
        }
        Row {
            spacing: Spacing.sm
            Button {
                objectName: "galleryUse"
                visible: !root.mine
                iconName: "add"
                text: "Use"
                onClicked: root.used()
            }
            Button {
                objectName: "galleryEdit"
                visible: root.mine
                type: "tonal"
                iconName: "edit"
                text: "Edit"
                onClicked: root.edited()
            }
            Button {
                objectName: "galleryPlace"
                visible: root.mine
                type: "tonal"
                iconName: "add_to_home_screen"
                text: "Add to desktop"
                onClicked: root.placed()
            }
        }
    }
}
