pragma ComponentBehavior: Bound
// One node of a widget (plan 4.3, D78), and through a Loader of this same file, its children. The parent sets the
// width; the height follows the content, unless the parent gives it more (a desktop widget made taller, D83): then a
// card or tile fills it, a column gives the extra to its last child that stretches (WidgetSpec.stretches), and a row
// stretches those to the same height. `textScale` sizes its text and icons (a desktop widget bigger than the
// default, D84). A card or a tile sets the colors its children draw with (`colors`,
// WidgetSpec.toneColors), so text on a primary tile is primaryOn. Text is never code: bindings are looked up in
// `values` (WidgetSpec.resolve). Only the drawn node's own component is created.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.common
import qs.components
import "WidgetSpec.js" as Spec

Item {
    id: root

    property var node: null
    property var values: ({})
    property int depth: 1
    property var colors: Spec.toneColors("surface_container")    // the enclosing card's or tile's
    property real textScale: 1
    readonly property color onColor: Colors[colors.on]
    readonly property color variantColor: Colors[colors.variant]

    function text(t) {
        return Spec.resolve(t, values);
    }
    function gap(name, fallback) {
        return Spacing[name ?? fallback] ?? Spacing[fallback];
    }
    // a type style at this widget's text scale
    function font(style) {
        return Type.font(Object.assign({}, style, { size: Math.round(style.size * textScale) }));
    }

    implicitHeight: body.item ? body.item.implicitHeight : 0
    implicitWidth: body.item ? body.item.implicitWidth : 0

    Loader {
        id: body
        width: root.width
        height: root.height
        sourceComponent: Spec.drawable(root.node, root.depth) ? ({
            row: rowNode, column: columnNode, grid: gridNode, card: blockNode, tile: blockNode, header: headerNode,
            heroImage: imageNode, stat: statNode, progress: progressNode, listRow: listRowNode, chip: chipNode,
            chart: chartNode
        })[root.node.type] : null
    }

    // ---- containers: their children are this same file again (WidgetChild.qml) ----
    Component {
        id: columnNode
        // A layout in an item: with a block it fills the height given, and the last block takes the extra; with
        // none it keeps its content's height, so the space stays below.
        Item {
            implicitHeight: column.implicitHeight
            ColumnLayout {
                id: column
                readonly property var kids: Spec.list(root.node.children) ?? []
                readonly property int stretch: {
                    for (let i = kids.length - 1; i >= 0; i--)
                        if (Spec.stretches(kids[i])) return i;
                    return -1;
                }
                width: parent.width
                height: stretch < 0 ? implicitHeight : parent.height
                spacing: root.gap(root.node.spacing, "md")
                Repeater {
                    model: root.node.children
                    delegate: WidgetChild {
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: shown ? shown.implicitHeight : 0
                        Layout.fillHeight: index === column.stretch
                        values: root.values
                        depth: root.depth + 1
                        colors: root.colors
                        textScale: root.textScale
                    }
                }
            }
        }
    }
    Component {
        id: rowNode
        // Children share the width equally, except chips, which keep their own (a row of chips packs to the left).
        RowLayout {
            id: row
            readonly property var kids: Spec.list(root.node.children) ?? []
            readonly property int shared: kids.filter(k => k.type !== "chip").length
            property real chipsWidth: 0
            function measure() {
                let w = 0;
                for (let i = 0; i < kids.length; i++)
                    if (kids[i].type === "chip") w += (rowItems.itemAt(i) as WidgetChild)?.shown?.implicitWidth ?? 0;
                chipsWidth = w;
            }
            readonly property real share: shared === 0 ? 0
                : Math.max(0, root.width - spacing * (kids.length - 1) - chipsWidth) / shared
            spacing: root.gap(root.node.spacing, "md")
            Repeater {
                id: rowItems
                model: root.node.children
                delegate: WidgetChild {
                    id: cell
                    readonly property bool chip: modelData.type === "chip"
                    readonly property real wanted: chip ? Math.min(shown?.implicitWidth ?? 0, root.width) : row.share
                    Layout.preferredWidth: wanted
                    Layout.minimumWidth: wanted
                    Layout.maximumWidth: wanted
                    Layout.preferredHeight: shown ? shown.implicitHeight : 0
                    Layout.fillHeight: Spec.stretches(modelData)
                    Layout.alignment: Qt.AlignTop
                    values: root.values
                    depth: root.depth + 1
                    colors: root.colors
                    textScale: root.textScale
                    onLoaded: if (chip) Qt.callLater(row.measure)
                    Connections {
                        target: cell.chip ? cell.shown : null
                        function onImplicitWidthChanged() { row.measure(); }
                    }
                }
            }
        }
    }
    Component {
        id: gridNode
        Grid {
            id: grid
            columns: root.node.columns
            spacing: root.gap(root.node.spacing, "md")
            Repeater {
                model: root.node.children
                delegate: WidgetChild {
                    width: (root.width - grid.spacing * (grid.columns - 1)) / grid.columns
                    values: root.values
                    depth: root.depth + 1
                    colors: root.colors
                    textScale: root.textScale
                }
            }
        }
    }
    // A card: a surface of its tone (surface_container unless given); a tile: a tinted block, smaller corners
    // and padding. Their children draw in the tone's colors.
    Component {
        id: blockNode
        Rectangle {
            id: block
            readonly property bool tile: root.node.type === "tile"
            readonly property var toneColors: Spec.toneColors(root.node.tone ?? "surface_container")
            readonly property real padding: tile ? Spacing.md : Spacing.lg
            implicitHeight: inner.implicitHeight + 2 * padding
            radius: tile ? Shapes.large : Shapes.extraLarge
            color: Colors[toneColors.fill]
            Column {
                id: inner
                x: block.padding
                y: block.padding
                width: block.width - 2 * block.padding
                spacing: block.tile ? Spacing.sm : Spacing.md
                Repeater {
                    model: root.node.children
                    delegate: WidgetChild {
                        width: inner.width
                        values: root.values
                        depth: root.depth + 1
                        colors: block.toneColors
                        textScale: root.textScale
                    }
                }
            }
        }
    }

    // ---- leaves ----
    Component {
        id: headerNode
        Row {
            spacing: Spacing.sm
            Icon {
                id: headerIcon
                visible: !!root.node.icon
                anchors.verticalCenter: parent.verticalCenter
                name: root.node.icon ?? ""
                size: Math.round(Spacing.xl * root.textScale)
                color: root.onColor
            }
            Text {
                width: root.width - (headerIcon.visible ? headerIcon.width + parent.spacing : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: root.text(root.node.title)
                elide: Text.ElideRight
                color: root.onColor
                font: root.font(Type.titleMedium)
            }
        }
    }
    Component {
        id: statNode
        Column {
            spacing: Spacing.xs
            Text {
                visible: !!root.node.label
                width: root.width
                text: root.text(root.node.label)
                elide: Text.ElideRight
                color: root.variantColor
                font: root.font(Type.labelLarge)
            }
            Row {
                spacing: Spacing.xs
                Text {
                    id: statValue
                    objectName: "widgetStatValue"
                    width: Math.min(implicitWidth, root.width - (unit.visible ? unit.implicitWidth + parent.spacing : 0))
                    text: root.text(root.node.value)
                    elide: Text.ElideRight
                    color: root.onColor
                    font: root.font(Type.displaySmall)
                }
                Text {
                    id: unit
                    visible: !!root.node.unit
                    anchors.baseline: statValue.baseline
                    text: root.node.unit ?? ""
                    color: root.variantColor
                    font: root.font(Type.titleMedium)
                }
            }
        }
    }
    Component {
        id: chartNode
        ChartNode {
            node: root.node
            values: root.values
            colors: root.colors
            textScale: root.textScale
        }
    }
    Component {
        id: progressNode
        // on a tinted card or tile the theme's track would vanish into it: the tone's On color, the track faint
        ProgressBar {
            objectName: "widgetProgress"
            value: Spec.progress(root.node.value, root.values)
            wavy: root.node.style === "wavy"
            indicatorShown: root.colors.tinted ? root.onColor : Colors[spec.activeIndicatorColor]
            trackShown: root.colors.tinted ? Qt.alpha(root.onColor, ControlSpec.stateOpacity.dragged)
                                            : Colors[spec.trackColor]
            stopShown: root.colors.tinted ? root.onColor : Colors[spec.stopColor]
        }
    }
    // One row, or one per item when it binds into a list (WidgetSpec.rows): each reads its own values.
    Component {
        id: listRowNode
        Column {
            Repeater {
                model: Spec.rows(root.node, root.values)
                delegate: Item {
                    id: listRow
                    required property var modelData
                    objectName: "widgetListRow"
                    width: root.width
                    implicitHeight: Math.max(listText.implicitHeight, Spacing.xl) + Spacing.sm * 2
                    height: implicitHeight
                    Icon {
                        id: listIcon
                        visible: !!root.node.icon
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.node.icon ?? ""
                        size: Math.round(Spacing.xl * root.textScale)
                        color: root.variantColor
                    }
                    Column {
                        id: listText
                        anchors.left: listIcon.visible ? listIcon.right : parent.left
                        anchors.leftMargin: listIcon.visible ? Spacing.lg : 0
                        anchors.right: trailing.visible ? trailing.left : parent.right
                        anchors.rightMargin: trailing.visible ? Spacing.lg : 0
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            text: Spec.resolve(root.node.title, listRow.modelData)
                            elide: Text.ElideRight
                            color: root.onColor
                            font: root.font(Type.bodyLarge)
                        }
                        Text {
                            visible: !!root.node.subtitle
                            width: parent.width
                            text: Spec.resolve(root.node.subtitle, listRow.modelData)
                            elide: Text.ElideRight
                            color: root.variantColor
                            font: root.font(Type.bodyMedium)
                        }
                    }
                    Icon {
                        id: trailing
                        visible: !!root.node.trailingIcon
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.node.trailingIcon ?? ""
                        size: Math.round(Spacing.xl * root.textScale)
                        color: root.variantColor
                    }
                }
            }
        }
    }
    // An assist chip's shape and outline (ControlSpec.chipSpec), in the enclosing colors.
    Component {
        id: chipNode
        Item {
            readonly property var spec: ControlSpec.chipSpec.assist
            implicitHeight: spec.containerHeight
            implicitWidth: chipRow.implicitWidth + 2 * ControlSpec.chipSpec.impl.contentPadding
            Rectangle {
                width: Math.min(root.width, chipRow.implicitWidth + 2 * ControlSpec.chipSpec.impl.contentPadding)
                height: parent.height
                radius: parent.spec.containerShape
                color: "transparent"
                border.width: parent.spec.flatOutlineWidth
                border.color: root.variantColor
                Row {
                    id: chipRow
                    x: ControlSpec.chipSpec.impl.contentPadding
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: ControlSpec.chipSpec.impl.gap
                    Icon {
                        visible: !!root.node.icon
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.node.icon ?? ""
                        size: Math.round(ControlSpec.chipSpec.assist.iconSize * root.textScale)
                        color: root.onColor
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.text(root.node.label)
                        color: root.onColor
                        font: root.font(Type.labelLarge)
                    }
                }
            }
        }
    }
    // An image cropped to its aspect with rounded corners; while it has no source (or does not load), a tinted
    // block with an image icon.
    Component {
        id: imageNode
        Item {
            id: hero
            readonly property string source: root.text(root.node.source)
            readonly property bool shown: picture.status === Image.Ready
            implicitHeight: Math.round(root.width * Spec.aspect(root.node.aspect))
            Rectangle {
                objectName: "widgetImagePlaceholder"
                anchors.fill: parent
                visible: !hero.shown
                radius: Shapes.large
                color: Colors.surfaceContainerHighest
                Icon {
                    anchors.centerIn: parent
                    name: "image"
                    size: Math.round(Spacing.xxl * root.textScale)
                    color: Colors.surfaceVariantOn
                }
            }
            Image {
                id: picture
                objectName: "widgetImage"
                anchors.fill: parent
                source: hero.source === Spec.MISSING ? "" : hero.source
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            // the rounded corners: only while a picture shows
            Loader {
                anchors.fill: parent
                active: hero.shown
                sourceComponent: Item {
                    Rectangle {
                        id: mask
                        anchors.fill: parent
                        radius: Shapes.large
                        layer.enabled: true
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: picture
                        maskEnabled: true
                        maskSource: mask
                    }
                }
            }
        }
    }
}
