// A container node's child (WidgetNode.qml): this same renderer again, one level deeper, in the container's colors.
// Created with its node and colors already set, so nothing fades in from the defaults; then bound to them.
import QtQuick

Loader {
    id: child
    required property var modelData
    property var values: ({})
    property int depth: 1
    property var colors: null
    readonly property WidgetNode shown: item as WidgetNode
    height: shown ? shown.implicitHeight : 0     // in a layout (a column or row node), the layout sets it
    Component.onCompleted: setSource(Qt.resolvedUrl("WidgetNode.qml"),
                                     { node: modelData, values: values, depth: depth, colors: colors, width: width })
    onLoaded: {
        shown.node = Qt.binding(() => child.modelData);
        shown.values = Qt.binding(() => child.values);
        shown.colors = Qt.binding(() => child.colors);
        shown.width = Qt.binding(() => child.width);
    }
}
