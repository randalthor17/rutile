// Everything the component kit offers, laid out for eyeballing. Pure QtQuick so it can be
// rendered offscreen; gallery.qml wraps it in a window.
import QtQuick
import qs.common
import qs.components
import qs.quicksettings
import qs.bar
import "GalleryHelpers.js" as Helpers
import "../common/MaterialShapes.js" as MaterialShapes

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

            GallerySection {
                title: "Shape library and morph"
                width: parent.width
                Row {
                    spacing: Spacing.xl
                    ShapeMorph {
                        id: morphDemo
                        objectName: "galleryMorph"
                        property int step: 0
                        readonly property var cycle: ["cookie9Sided", "softBurst", "heart", "pill", "clover4Leaf", "circle"]
                        width: 160
                        height: 160
                        shape: cycle[step % cycle.length]
                        color: Colors.primaryContainer
                    }
                    Column {
                        spacing: Spacing.sm
                        anchors.verticalCenter: parent.verticalCenter
                        Button {
                            objectName: "galleryMorphNext"
                            text: "Morph"
                            type: "tonal"
                            size: "s"
                            iconName: "auto_awesome"
                            onClicked: morphDemo.step++
                        }
                        Text {
                            text: morphDemo.shape
                            color: Colors.surfaceVariantOn
                            font: Type.font(Type.labelMedium)
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: Spacing.lg
                    Repeater {
                        model: MaterialShapes.names
                        delegate: Column {
                            id: libraryItem
                            required property string modelData
                            width: 72
                            spacing: Spacing.xs
                            ShapeMorph {
                                objectName: "galleryShape"
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 56
                                height: 56
                                shape: libraryItem.modelData
                                color: Colors.secondary
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: libraryItem.modelData
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

            // ---- expressive slider sizes, track icons ----
            GallerySection {
                title: "Slider sizes and track icons"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.lg

                    // Quick Settings: brightness and volume with their icon at the end of the track.
                    Rectangle {
                        width: Math.min(parent.width, 460)
                        height: qsSliders.height + 2 * Spacing.lg
                        radius: Shapes.extraLarge
                        color: Colors.surfaceContainer
                        Column {
                            id: qsSliders
                            x: Spacing.lg
                            y: Spacing.lg
                            width: parent.width - 2 * Spacing.lg
                            spacing: Spacing.sm
                            Repeater {
                                model: [
                                    { icon: "brightness_medium", button: "dark_mode", value: 0.95 },
                                    { icon: "music_note", button: "tune", value: 0.7 }
                                ]
                                delegate: Row {
                                    id: qsRow
                                    required property var modelData
                                    spacing: Spacing.sm
                                    Slider {
                                        objectName: "galleryQsSlider"
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: qsRow.parent.width - ControlSpec.iconButtonSizes.s.width.default - qsRow.spacing
                                        size: "m"
                                        endIcon: qsRow.modelData.icon
                                        value: qsRow.modelData.value
                                    }
                                    IconButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        iconName: qsRow.modelData.button
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: ["s", "m", "l", "xl"]
                        delegate: Slider {
                            required property string modelData
                            objectName: "gallerySizedSlider"
                            width: 360
                            size: modelData
                            value: 0.5
                            endIcon: "volume_up"
                        }
                    }
                    Text {
                        text: "Sizes s, m, l and xl (xs is the slider above). Track icons show from m up; Android uses one, at the end."
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Colors.surfaceVariantOn
                        font: Type.font(Type.labelMedium)
                    }
                }
            }

            // ---- quick settings: tiles, chips, list items ----
            GallerySection {
                title: "Tiles, chips, list items"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.lg
                    Flow {
                        width: Math.min(parent.width, 640)
                        spacing: Spacing.sm
                        Tile { objectName: "galleryTile"; text: "Wi-Fi"; secondaryText: "Home"; iconName: "wifi"; active: true; dualTarget: true; width: 300 }
                        Tile { objectName: "galleryTile"; text: "Bluetooth"; secondaryText: "Off"; iconName: "bluetooth"; dualTarget: true; width: 300 }
                        Tile { objectName: "galleryTile"; text: "Do not disturb"; secondaryText: "On"; iconName: "do_not_disturb_on"; active: true; width: 300 }
                        Tile { objectName: "galleryTile"; text: "Night light"; secondaryText: "Off"; iconName: "nightlight"; width: 300 }
                        Tile { objectName: "galleryTile"; text: "Airplane mode"; secondaryText: "Unavailable"; iconName: "flight"; available: false; width: 300 }
                        Tile { objectName: "galleryTile"; iconName: "flashlight_on"; iconOnly: true; active: true }
                        Tile { objectName: "galleryTile"; iconName: "screen_rotation"; iconOnly: true }
                    }
                    Flow {
                        width: parent.width
                        spacing: Spacing.sm
                        Chip { objectName: "galleryChip"; text: "Assist"; iconName: "event" }
                        Chip { objectName: "galleryChip"; text: "Elevated"; iconName: "share"; elevated: true }
                        Chip { objectName: "galleryChip"; text: "Filter"; type: "filter" }
                        Chip { objectName: "galleryChip"; text: "Selected"; type: "filter"; selected: true }
                        Chip { objectName: "galleryChip"; text: "Dropdown"; type: "filter"; trailingIconName: "arrow_drop_down" }
                        Chip { objectName: "galleryChip"; text: "Disabled"; type: "filter"; selected: true; enabled: false }
                    }
                    Rectangle {
                        width: Math.min(parent.width, 420)
                        height: group.height + 2 * Spacing.sm
                        radius: Shapes.large
                        color: Colors.surfaceContainer
                        Column {
                            id: group
                            x: Spacing.sm
                            y: Spacing.sm
                            width: parent.width - 2 * Spacing.sm
                            spacing: ControlSpec.listSpec.segmentedGap
                            ListItem { objectName: "galleryListItem"; width: parent.width; position: "first"; text: "Network"; supportingText: "Wi-Fi, mobile, hotspot"; iconName: "wifi" }
                            ListItem { objectName: "galleryListItem"; width: parent.width; position: "middle"; text: "Bluetooth"; iconName: "bluetooth"; Switch { checked: true } }
                            ListItem { objectName: "galleryListItem"; width: parent.width; position: "middle"; text: "Display"; iconName: "brightness_6"; selected: true }
                            ListItem { objectName: "galleryListItem"; width: parent.width; position: "last"; text: "Storage"; trailingText: "64 GB free"; iconName: "storage" }
                        }
                    }
                }
            }

            // ---- editable grid: Quick Settings tiles ----
            GallerySection {
                title: "Quick Settings panel"
                width: parent.width
                Column {
                    width: parent.width
                    spacing: Spacing.md
                    // A demo backend that applies what the panel asks, so tiles and sliders respond.
                    QtObject {
                        id: demoBackend
                        property bool brightnessAvailable: true
                        property real brightness: 0.95
                        property bool volumeAvailable: true
                        property real volume: 0.7
                        property bool muted: false
                        property bool micAvailable: true
                        property bool micMuted: false
                        property bool wifiAvailable: true
                        property bool wifiEnabled: true
                        property string wifiName: "Home"
                        property real wifiSignal: 0.8
                        property bool wiredConnected: false
                        property bool batteryAvailable: true
                        property real battery: 0.82
                        property bool charging: false
                        property bool bluetoothAvailable: true
                        property bool bluetoothEnabled: false
                        property string bluetoothDevice: ""
                        readonly property bool darkTheme: Colors.mode === "dark"
                        function setBrightness(v) { brightness = v; }
                        function setVolume(v) { volume = v; muted = false; }
                        function setMicMuted(m) { micMuted = m; }
                        function setWifiEnabled(b) { wifiEnabled = b; }
                        function setBluetoothEnabled(b) { bluetoothEnabled = b; }
                        function setDarkTheme(b) { Colors.mode = b ? "dark" : "light"; }
                        function setAirplaneMode(b) { wifiEnabled = !b; bluetoothEnabled = !b; }
                        function refresh() {}
                    }
                    StatusPill {
                        id: demoPill
                        objectName: "galleryStatusPill"
                        backend: demoBackend
                        open: demoPanel.visible
                        onClicked: demoPanel.visible = !demoPanel.visible
                    }
                    QuickSettingsPanel {
                        id: demoPanel
                        objectName: "galleryQuickSettings"
                        backend: demoBackend
                        // a power choice hides the panel; here the pill brings it back
                        onHidden: { visible = false; shown = true; }
                    }
                    Text {
                        text: "The shell's status pill and panel with a demo backend; click the pill. In the shell: "
                              + "quickshell -p shell/shell.qml, then click the pill at the top right"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Colors.surfaceVariantOn
                        font: Type.font(Type.labelMedium)
                    }
                }
            }

            GallerySection {
                title: "Editable grid (Quick Settings tiles)"
                width: parent.width
                Column {
                    id: qsDemo
                    width: parent.width
                    spacing: Spacing.md

                    // Demo data: a real panel saves only id and size, and looks the rest up by id.
                    readonly property var startTiles: [
                        { id: "wifi", w: 2, text: "Wi-Fi", secondaryText: "Home", iconName: "wifi", dualTarget: true },
                        { id: "bluetooth", w: 2, text: "Bluetooth", secondaryText: "Off", iconName: "bluetooth", dualTarget: true },
                        { id: "dnd", text: "Do not disturb", iconName: "do_not_disturb_on" },
                        { id: "rotate", text: "Auto-rotate", iconName: "screen_rotation" },
                        { id: "dark", text: "Dark theme", iconName: "contrast" },
                        { id: "mic", text: "Mic access", secondaryText: "Available", iconName: "mic" },
                        { id: "camera", text: "Camera access", secondaryText: "Available", iconName: "videocam" },
                        { id: "flashlight", text: "Flashlight", iconName: "flashlight_on" },
                        { id: "keyboard", text: "Keyboard", iconName: "keyboard" }
                    ]

                    Row {
                        spacing: Spacing.sm
                        Button {
                            objectName: "galleryGridEdit"
                            text: qsGrid.editMode ? "Done" : "Edit tiles"
                            type: qsGrid.editMode ? "filled" : "tonal"
                            onClicked: qsGrid.editMode = !qsGrid.editMode
                        }
                        Button {
                            text: "Remove"
                            type: "outlined"
                            enabled: qsGrid.editMode && qsGrid.selectedIndex >= 0
                            onClicked: qsGrid.items = qsGrid.items.filter((item, i) => i !== qsGrid.selectedIndex)
                        }
                        Button {
                            text: "Reset"
                            type: "text"
                            onClicked: qsGrid.items = qsDemo.startTiles
                        }
                        Switch {
                            id: rtlSwitch
                            objectName: "galleryGridRtl"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Right to left"
                            color: Colors.surfaceVariantOn
                            font: Type.font(Type.labelLarge)
                        }
                    }

                    Rectangle {
                        width: Math.min(parent.width, 460)
                        height: qsGrid.height + 2 * Spacing.lg
                        radius: Shapes.extraLarge
                        color: Colors.surfaceContainer
                        border.width: qsGrid.editMode ? Spacing.xs / 2 : 0
                        border.color: Colors.primary
                        // What a right-to-left locale sets once at the shell's root.
                        LayoutMirroring.enabled: rtlSwitch.checked
                        LayoutMirroring.childrenInherit: true

                        EditableGrid {
                            id: qsGrid
                            objectName: "galleryGrid"
                            x: Spacing.lg
                            y: Spacing.lg
                            width: parent.width - 2 * Spacing.lg
                            columns: 4
                            maxRows: 5
                            items: qsDemo.startTiles
                            slotRadius: ControlSpec.tileSpec.inactiveCornerRadius
                            delegate: Tile {
                                property var modelData: ({})
                                text: modelData.text ?? ""
                                secondaryText: modelData.secondaryText ?? ""
                                iconName: modelData.iconName ?? ""
                                dualTarget: modelData.dualTarget ?? false
                                iconOnly: !(modelData.w > 1)
                            }
                        }
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
