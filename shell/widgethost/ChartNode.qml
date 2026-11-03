// A widget's chart (D87): a line or area chart of numbers over time (a window of `points` samples, the newest at the
// right), bars of numbers or of labelled values, a pie
// or donut of labelled values with a legend, or a gauge of one value. Data comes as WidgetSpec reads it (chartValues,
// chartSeries, chartNumber), never evaluated. Drawn with Rectangles for bars and QtQuick.Shapes' curve renderer for
// lines and arcs (no Canvas, D31); only the kind drawn is created. On a tinted card or tile, a series without its
// own tone takes the tone's On color, fading from one series to the next; elsewhere primary, tertiary, secondary,
// error in turn. `size` (small, medium, large) sets the plot's height.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.common
import "WidgetSpec.js" as Spec

Item {
    id: root

    property var node: ({})
    property var values: ({})
    property var colors: Spec.toneColors("surface_container")
    property real textScale: 1

    readonly property string kind: Spec.CHART_KINDS.indexOf(node.kind) >= 0 ? node.kind : "line"
    readonly property var lines: kind === "line" || kind === "area" ? Spec.chartLines(node, values) : []
    readonly property var numbers: lines.length === 1 ? lines[0].numbers : Spec.chartValues(node, values)
    readonly property var allNumbers: lines.length > 1 ? [].concat.apply([], lines.map(l => l.numbers)) : numbers
    readonly property var series: Spec.chartSeries(node, values)
    readonly property real gaugeValue: Spec.chartNumber(node.value, values)
    readonly property bool bySeries: kind === "pie" || kind === "donut" || (kind === "bar" && numbers.length === 0)
    readonly property bool multiLine: lines.length > 1
    readonly property var range: Spec.chartScale(node, kind === "gauge" ? (isFinite(gaugeValue) ? [gaugeValue] : [])
                                                 : bySeries ? series.map(s => s.value) : allNumbers)
    readonly property real plotHeight: Spacing.xxxl * (({ small: 1, medium: 2, large: 3 })[node.size ?? "medium"] ?? 2)
    readonly property real stroke: Spacing.xs * 0.75 * textScale
    readonly property color onColor: Colors[colors.on]
    readonly property color variantColor: Colors[colors.variant]
    readonly property color accent: node.tone ? Colors[Spec.camel(node.tone)] : colors.tinted ? onColor : Colors.primary
    readonly property string unit: node.unit ?? ""

    function font(style) {
        return Type.font(Object.assign({}, style, { size: Math.round(style.size * textScale) }));
    }
    // a series' color: its own tone, or the next one (on a tinted surface: its On color, fainter each time)
    function seriesColor(s, i) {
        if (s.tone && (node.series?.[i]?.tone || !colors.tinted))
            return Colors[Spec.camel(s.tone)];
        return Qt.alpha(onColor, Math.max(0.35, 1 - i * 0.2));
    }
    // a line's color: its tone, or the chart's accent for a lone line; on a tinted surface, its On color, fading
    function lineColor(line, i) {
        if (line.tone && (node.series?.[i]?.tone || !colors.tinted || (i === 0 && node.tone)))
            return Colors[Spec.camel(line.tone)];
        return i === 0 ? accent : Qt.alpha(onColor, Math.max(0.35, 1 - i * 0.3));
    }
    function shown(v) {
        return Spec.chartText(v) + (unit !== "" && isFinite(v) ? " " + unit : "");
    }

    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth

    Column {
        id: content
        width: root.width
        spacing: Spacing.sm

        // line, area and bar charts: the label, and the newest value
        Item {
            visible: (root.kind === "line" || root.kind === "area" || root.kind === "bar") && !!(root.node.label || root.unit)
            width: parent.width
            height: visible ? Math.max(caption.implicitHeight, latest.implicitHeight) : 0
            Text {
                id: caption
                objectName: "chartCaption"
                anchors.left: parent.left
                anchors.right: latest.left
                anchors.baseline: latest.baseline
                elide: Text.ElideRight
                text: Spec.resolve(root.node.label ?? "", root.values)
                color: root.variantColor
                font: root.font(Type.labelLarge)
            }
            Text {
                id: latest
                objectName: "chartLatest"
                anchors.right: parent.right
                visible: !root.bySeries && !root.multiLine
                text: root.numbers.length ? root.shown(root.numbers[root.numbers.length - 1]) : Spec.MISSING
                color: root.onColor
                font: root.font(Type.titleMedium)
            }
        }
        // several lines: each one's label and newest value, in its color
        Flow {
            visible: root.multiLine
            width: parent.width
            spacing: Spacing.md
            Repeater {
                model: root.multiLine ? root.lines : []
                delegate: Row {
                    id: key
                    required property var modelData
                    required property int index
                    spacing: Spacing.xs
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Spacing.sm * root.textScale
                        height: width
                        radius: width / 2
                        color: root.lineColor(key.modelData, key.index)
                    }
                    Text {
                        objectName: "chartLineLegend"
                        text: key.modelData.label + "  " + (key.modelData.numbers.length
                              ? root.shown(key.modelData.numbers[key.modelData.numbers.length - 1]) : Spec.MISSING)
                        color: root.onColor
                        font: root.font(Type.labelLarge)
                    }
                }
            }
        }
        Loader {
            width: parent.width
            sourceComponent: ({ line: lineChart, area: lineChart, bar: barChart, pie: roundChart, donut: roundChart,
                                gauge: gaugeChart })[root.kind]
        }
    }

    Component {
        id: lineChart
        Item {
            id: plot
            readonly property int span: Spec.chartSpan(root.node, Math.max.apply(null, [0].concat(root.lines.map(l => l.numbers.length))))
            height: root.plotHeight
            Repeater {
                model: root.lines
                delegate: Shape {
                    id: line
                    required property var modelData
                    required property int index
                    readonly property color color: root.lineColor(modelData, index)
                    readonly property var points: Spec.linePoints(modelData.numbers, root.range, plot.width - root.stroke,
                                                                  plot.height - root.stroke, plot.span)
                        .map(p => Qt.point(p.x + root.stroke / 2, p.y + root.stroke / 2))
                    objectName: "chartLine"
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: root.kind === "area" && line.points.length ? Qt.alpha(line.color, root.multiLine ? 0.15 : 0.25) : "transparent"
                        PathPolyline {
                            path: line.points.length
                                  ? line.points.concat([Qt.point(line.points[line.points.length - 1].x, plot.height),
                                                        Qt.point(line.points[0].x, plot.height)])
                                  : []
                        }
                    }
                    ShapePath {
                        strokeColor: line.points.length ? line.color : "transparent"
                        strokeWidth: root.stroke
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline { path: line.points }
                    }
                }
            }
            // the baseline, faint
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.alpha(root.variantColor, 0.3)
            }
        }
    }

    Component {
        id: barChart
        Row {
            id: bars
            objectName: "chartBars"
            readonly property var entries: root.bySeries ? root.series : root.numbers.map(v => ({ label: "", value: v, tone: "" }))
            readonly property bool labelled: root.bySeries
            spacing: labelled ? Spacing.sm : Spacing.xs / 2
            Repeater {
                model: bars.entries
                delegate: Column {
                    id: bar
                    required property var modelData
                    required property int index
                    width: (root.width - bars.spacing * (bars.entries.length - 1)) / Math.max(1, bars.entries.length)
                    spacing: Spacing.xs
                    Item {
                        width: parent.width
                        height: root.plotHeight
                        Rectangle {
                            objectName: "chartBar"
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(root.stroke / 2, Spec.chartPosition(bar.modelData.value, root.range) * parent.height)
                            radius: Math.min(width / 2, Spacing.xs)
                            color: bars.labelled ? root.seriesColor(bar.modelData, bar.index) : root.accent
                        }
                    }
                    Text {
                        visible: bars.labelled
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: bar.modelData.label
                        color: root.variantColor
                        font: root.font(Type.labelSmall)
                    }
                    Text {
                        visible: bars.labelled
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.shown(bar.modelData.value)
                        color: root.onColor
                        font: root.font(Type.labelMedium)
                    }
                }
            }
        }
    }

    // A pie (slices to the center) or donut (a ring), with a legend beside it: label, value and share.
    Component {
        id: roundChart
        Row {
            id: round
            readonly property real diameter: Math.min(root.width / 2, root.plotHeight * 1.5)
            readonly property real thickness: root.kind === "pie" ? diameter / 2 : diameter * 0.16
            readonly property var parts: Spec.slices(root.series)
            spacing: Spacing.lg
            Item {
                objectName: "chartRound"
                width: round.diameter
                height: round.diameter
                Repeater {
                    model: round.parts
                    delegate: Shape {
                        id: slice
                        required property var modelData
                        required property int index
                        objectName: "chartSlice"
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        visible: modelData.sweep > 0
                        ShapePath {
                            strokeColor: root.seriesColor(slice.modelData, slice.index)
                            strokeWidth: round.thickness
                            fillColor: "transparent"
                            capStyle: ShapePath.FlatCap
                            PathAngleArc {
                                centerX: round.diameter / 2
                                centerY: round.diameter / 2
                                radiusX: (round.diameter - round.thickness) / 2
                                radiusY: (round.diameter - round.thickness) / 2
                                startAngle: slice.modelData.start
                                sweepAngle: slice.modelData.sweep
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    width: round.diameter - 2 * round.thickness
                    visible: root.kind === "donut"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: Spec.resolve(root.node.label ?? "", root.values)
                    color: root.onColor
                    font: root.font(Type.labelLarge)
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: root.width - round.diameter - round.spacing
                spacing: Spacing.xs
                Repeater {
                    model: round.parts
                    delegate: Row {
                        id: entry
                        required property var modelData
                        required property int index
                        width: parent.width
                        spacing: Spacing.sm
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Spacing.sm * root.textScale
                            height: width
                            radius: width / 2
                            color: root.seriesColor(entry.modelData, entry.index)
                        }
                        Text {
                            objectName: "chartLegend"
                            width: parent.width - Spacing.sm * root.textScale - entry.spacing
                            elide: Text.ElideRight
                            text: entry.modelData.label + "  " + root.shown(entry.modelData.value)
                            color: root.onColor
                            font: root.font(Type.labelMedium)
                        }
                    }
                }
            }
        }
    }

    // A gauge: three quarters of a ring, filled to the value, the value and label inside.
    Component {
        id: gaugeChart
        Item {
            id: gauge
            readonly property real diameter: Math.min(root.width, root.plotHeight * 1.5)
            readonly property real thickness: Spacing.sm * root.textScale
            readonly property real position: isFinite(root.gaugeValue) ? Spec.chartPosition(root.gaugeValue, root.range) : 0
            height: diameter
            Shape {
                objectName: "chartGauge"
                x: (parent.width - gauge.diameter) / 2
                width: gauge.diameter
                height: gauge.diameter
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.alpha(root.variantColor, 0.25)
                    strokeWidth: gauge.thickness
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: gauge.diameter / 2
                        centerY: gauge.diameter / 2
                        radiusX: (gauge.diameter - gauge.thickness) / 2
                        radiusY: (gauge.diameter - gauge.thickness) / 2
                        startAngle: 135
                        sweepAngle: 270
                    }
                }
                ShapePath {
                    strokeColor: gauge.position > 0 ? root.accent : "transparent"
                    strokeWidth: gauge.thickness
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: gauge.diameter / 2
                        centerY: gauge.diameter / 2
                        radiusX: (gauge.diameter - gauge.thickness) / 2
                        radiusY: (gauge.diameter - gauge.thickness) / 2
                        startAngle: 135
                        sweepAngle: 270 * gauge.position
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                Text {
                    objectName: "chartGaugeValue"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.shown(root.gaugeValue)
                    color: root.onColor
                    // as big as the ring leaves room for
                    font: root.font(({ small: Type.titleMedium, medium: Type.headlineSmall, large: Type.displaySmall })[root.node.size ?? "medium"]
                                    ?? Type.headlineSmall)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text !== ""
                    width: Math.min(implicitWidth, gauge.diameter - 2 * gauge.thickness)
                    elide: Text.ElideRight
                    text: Spec.resolve(root.node.label ?? "", root.values)
                    color: root.variantColor
                    font: root.font(Type.labelMedium)
                }
            }
        }
    }
}
