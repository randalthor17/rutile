// A titled block of the gallery.
import QtQuick
import qs.common

Column {
    id: root

    property string title: ""
    default property alias body: bodyColumn.data

    spacing: Spacing.md

    Text {
        text: root.title
        color: Colors.surfaceOn
        font: Type.font(Type.titleLargeEmphasized)
    }

    Column {
        id: bodyColumn
        width: root.width
    }
}
