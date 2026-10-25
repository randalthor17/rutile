// Everything the component kit offers, laid out for eyeballing. Pure QtQuick so it can be
// rendered offscreen; gallery.qml wraps it in a window.
import QtQuick
import qs.common
import qs.components
import "GalleryHelpers.js" as Helpers

Rectangle {
    id: root

    readonly property alias content: column
    readonly property alias flickable: flick
    readonly property int pad: Spacing.xl

    color: Colors.surface

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + root.pad * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            x: root.pad
            y: root.pad
            width: flick.width - root.pad * 2
            spacing: Spacing.xxl

            // ---- header ----
            Row {
                width: parent.width
                spacing: Spacing.lg

                Column {
                    width: parent.width - themeToggle.width - Spacing.lg
                    spacing: Spacing.xs
                    Text {
                        text: "Rutile component gallery"
                        color: Colors.surfaceOn
                        font: Type.font(Type.headlineMediumEmphasized)
                    }
                    Text {
                        text: "Mode: " + Colors.mode + "   Seed: " + Colors.sourceColor + "   Palette loaded: " + Colors.loaded
                        color: Colors.surfaceVariantOn
                        font: Type.font(Type.bodyMedium)
                    }
                }

                IconButton {
                    id: themeToggle
                    objectName: "themeToggle"
                    iconName: checked ? "light_mode" : "dark_mode"
                    type: "tonal"
                    size: "m"
                    toggle: true
                    checked: Colors.mode === "light"
                    onToggled: c => { Colors.mode = c ? "light" : "dark"; }
                }
            }

            // ---- colors ----
            GallerySection {
                title: "Color roles"
                width: parent.width
                Flow {
                    width: parent.width
                    spacing: Spacing.sm
                    Repeater {
                        model: Colors.roles
                        delegate: Rectangle {
                            id: swatch
                            objectName: "swatch"
                            required property string modelData
                            readonly property color fill: Colors[Helpers.roleProperty(swatch.modelData)]
                            width: 172
                            height: 52
                            radius: Shapes.small
                            color: swatch.fill
                            border.width: 1
                            border.color: Colors.outlineVariant
                            Text {
                                anchors.fill: parent
                                anchors.margins: Spacing.sm
                                text: swatch.modelData
                                color: Helpers.luminance(swatch.fill) > 0.5 ? Qt.rgba(0, 0, 0, 0.87) : Qt.rgba(1, 1, 1, 0.95)
                                font: Type.font(Type.labelSmall)
                                wrapMode: Text.WrapAnywhere
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }

            // ---- shapes ----
            GallerySection {
                title: "Shape scale"
                width: parent.width
                Flow {
                    width: parent.width
                    spacing: Spacing.lg
                    Repeater {
                        model: ["none", "extraSmall", "small", "medium", "large", "largeIncreased", "extraLarge", "extraLargeIncreased", "extraExtraLarge", "full"]
                        delegate: Column {
                            id: shapeItem
                            required property string modelData
                            spacing: Spacing.xs
                            Rectangle {
                                width: 88
                                height: 88
                                radius: Shapes[shapeItem.modelData]
                                color: Colors.secondaryContainer
                            }
                            Text {
                                text: shapeItem.modelData + "\n" + (Shapes[shapeItem.modelData] === 9999 ? "full" : Shapes[shapeItem.modelData])
                                color: Colors.surfaceVariantOn
                                font: Type.font(Type.labelSmall)
                            }
                        }
                    }
                }
            }

            // ---- type ----
            GallerySection {
                title: "Type scale"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.sm
                    Repeater {
                        model: Type.styleNames
                        delegate: Row {
                            id: styleRow
                            objectName: "typeRow"
                            required property string modelData
                            spacing: Spacing.lg
                            Text {
                                width: 230
                                text: styleRow.modelData
                                color: Colors.surfaceVariantOn
                                font: Type.font(Type.labelMedium)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Sphinx of black quartz, judge my vow"
                                color: Colors.surfaceOn
                                font: Type.font(Type[styleRow.modelData])
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // ---- buttons ----
            GallerySection {
                title: "Buttons (types x sizes)"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.lg
                    Repeater {
                        model: ["xs", "s", "m", "l", "xl"]
                        delegate: Column {
                            id: sizeBlock
                            required property string modelData
                            width: parent.width
                            spacing: Spacing.sm
                            Text {
                                text: "size " + sizeBlock.modelData
                                color: Colors.surfaceVariantOn
                                font: Type.font(Type.labelMedium)
                            }
                            Flow {
                                width: sizeBlock.width
                                spacing: Spacing.md
                                Repeater {
                                    model: Helpers.pairsBySize(sizeBlock.modelData)
                                    delegate: Button {
                                        required property var modelData
                                        type: modelData.kind
                                        size: modelData.size
                                        text: modelData.kind
                                        iconName: "add"
                                    }
                                }
                            }
                        }
                    }
                }
            }

            GallerySection {
                title: "Buttons (shape, toggle, disabled)"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.md
                    Flow {
                        width: parent.width
                        spacing: Spacing.md
                        Button { text: "Square"; type: "filled"; shape: "square"; size: "m" }
                        Button { text: "Square tonal"; type: "tonal"; shape: "square"; size: "m"; iconName: "edit" }
                        Button { text: "Toggle"; type: "filled"; size: "m"; toggle: true; iconName: "favorite" }
                        Button { text: "Toggle square"; type: "tonal"; size: "m"; shape: "square"; toggle: true }
                        Button { text: "Outlined toggle"; type: "outlined"; size: "m"; toggle: true }
                    }
                    Flow {
                        width: parent.width
                        spacing: Spacing.md
                        Button { text: "Disabled"; type: "filled"; size: "m"; enabled: false }
                        Button { text: "Disabled"; type: "tonal"; size: "m"; enabled: false }
                        Button { text: "Disabled"; type: "outlined"; size: "m"; enabled: false }
                        Button { text: "Disabled"; type: "text"; size: "m"; enabled: false }
                        Button { text: "Disabled"; type: "elevated"; size: "m"; enabled: false }
                    }
                }
            }

            // ---- icon buttons ----
            GallerySection {
                title: "Icon buttons (types x sizes)"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.md
                    Repeater {
                        model: ["standard", "filled", "tonal", "outlined"]
                        delegate: Row {
                            id: typeRow
                            required property string modelData
                            spacing: Spacing.md
                            Text {
                                width: 90
                                text: typeRow.modelData
                                color: Colors.surfaceVariantOn
                                font: Type.font(Type.labelMedium)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Repeater {
                                model: Helpers.pairs(typeRow.modelData, ["xs", "s", "m", "l", "xl"])
                                delegate: IconButton {
                                    required property var modelData
                                    iconName: "settings"
                                    type: modelData.kind
                                    size: modelData.size
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                    Row {
                        spacing: Spacing.md
                        Text {
                            width: 90
                            text: "toggle"
                            color: Colors.surfaceVariantOn
                            font: Type.font(Type.labelMedium)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        IconButton { iconName: "wifi"; type: "filled"; size: "m"; toggle: true; checked: true }
                        IconButton { iconName: "bluetooth"; type: "tonal"; size: "m"; toggle: true }
                        IconButton { iconName: "star"; type: "outlined"; size: "m"; toggle: true; shape: "square" }
                        IconButton { iconName: "add"; type: "filled"; size: "s"; widthVariant: "narrow" }
                        IconButton { iconName: "add"; type: "filled"; size: "s"; widthVariant: "wide" }
                        IconButton { iconName: "delete"; type: "filled"; size: "m"; enabled: false }
                    }
                }
            }

            // ---- switches, sliders, progress ----
            GallerySection {
                title: "Switch, slider, progress"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.lg
                    Row {
                        spacing: Spacing.xl
                        Switch { objectName: "gallerySwitch" }
                        Switch { objectName: "gallerySwitch"; checked: true }
                        Switch { objectName: "gallerySwitch"; checkedIcon: "check"; uncheckedIcon: "close" }
                        Switch { objectName: "gallerySwitch"; checkedIcon: "check"; uncheckedIcon: "close"; checked: true }
                        Switch { objectName: "gallerySwitch"; enabled: false }
                        Switch { objectName: "gallerySwitch"; enabled: false; checked: true }
                    }
                    Slider { objectName: "gallerySlider"; id: demoSlider; width: 360; value: 0.4 }
                    Slider { objectName: "gallerySlider"; width: 360; from: 0; to: 10; stepSize: 1; value: 3 }
                    Slider { objectName: "gallerySlider"; width: 360; value: 0.6; enabled: false }
                    ProgressBar { objectName: "galleryProgress"; width: 360; value: demoSlider.value }
                    ProgressBar { objectName: "galleryProgress"; width: 360; value: demoSlider.value; wavy: true }
                    Text {
                        text: "The progress bars follow the first slider."
                        color: Colors.surfaceVariantOn
                        font: Type.font(Type.labelMedium)
                    }
                }
            }

            // ---- motion ----
            GallerySection {
                title: "Motion (click to move)"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.sm
                    Repeater {
                        model: [
                            { label: "spatial fast", axis: "spatial", speed: "fast" },
                            { label: "spatial default", axis: "spatial", speed: "default" },
                            { label: "spatial slow", axis: "spatial", speed: "slow" },
                            { label: "effects fast", axis: "effects", speed: "fast" },
                            { label: "effects default", axis: "effects", speed: "default" }
                        ]
                        delegate: Item {
                            id: lane
                            required property var modelData
                            width: parent.width
                            height: 44
                            property bool atEnd: false

                            Text {
                                id: laneLabel
                                width: 150
                                text: lane.modelData.label
                                color: Colors.surfaceVariantOn
                                font: Type.font(Type.labelMedium)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Surface {
                                x: laneLabel.width
                                width: parent.width - laneLabel.width
                                height: 4
                                radius: Shapes.full
                                tone: Colors.surfaceContainerHighest
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Spring {
                                id: pos
                                target: lane.atEnd ? 1 : 0
                                stiffness: Motion.spring(lane.modelData.axis, lane.modelData.speed).stiffness
                                dampingRatio: Motion.spring(lane.modelData.axis, lane.modelData.speed).dampingRatio
                            }
                            Rectangle {
                                width: 36
                                height: 36
                                radius: Shapes.full
                                color: Colors.primary
                                x: laneLabel.width + pos.value * (lane.width - laneLabel.width - width)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: lane.atEnd = !lane.atEnd
                            }
                        }
                    }
                }
            }
        }
    }
}
