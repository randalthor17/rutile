pragma ComponentBehavior: Bound
// The Quick Settings panel (plan 2.6) as Googlebook shows it: a header (edit tiles, settings, power),
// the brightness and volume sliders, and the tiles on the EditableGrid. Plain QtQuick: everything it shows
// and does goes through `backend` (QuickSettingsBackend.qml in the shell; a fake in tests and the gallery),
// so it renders and tests offscreen. Tiles are controlled (D33): a toggle asks the backend, and the tile
// changes when the system does. The sliders follow the backend except while dragged. It grows in from the top
// right when created and shrinks away when `shown` turns false, then reports `hidden` (the window unloads then).
//
// The backend has: brightnessAvailable, brightness, volumeAvailable, volume, muted, micAvailable,
// micMuted, wifiAvailable, wifiEnabled, wifiName, bluetoothAvailable, bluetoothEnabled, bluetoothDevice,
// darkTheme; and setBrightness(v), setVolume(v), setMicMuted(b), setWifiEnabled(b),
// setBluetoothEnabled(b), setDarkTheme(b), setAirplaneMode(b), powerAction(id) (PowerActions.js), refresh().
import QtQuick
import qs.common
import qs.components

Rectangle {
    id: root

    required property var backend      // duck-typed: the real backend or a fake with the same members

    // Saved data, {id, w}: which tiles, in which order and size. Kept in memory until settings
    // persistence (plan 2.5); `tilesEdited` reports each change for whoever saves it.
    property var tiles: defaultTiles
    readonly property var defaultTiles: [
        { id: "wifi", w: 2 }, { id: "bluetooth", w: 2 },
        { id: "mic", w: 1 }, { id: "dark", w: 1 }, { id: "airplane", w: 1 }
    ]
    property alias editMode: grid.editMode
    property bool powerMenuOpen: false
    // Open and close motion: false shrinks and fades the panel away, then `hidden` fires.
    property bool shown: true
    readonly property real appearProgress: appear.value
    readonly property bool brightnessShown: brightnessRow.visible
    readonly property real panelWidth: 412

    signal tilesEdited(var tiles)
    signal settingsRequested()
    signal powerActionTaken(string id)
    signal hidden()
    signal soundSettingsRequested()
    signal detailsRequested(string tileId)
    // The window this panel is in lost keyboard focus (another window took it), after having had it. The
    // window's state, not the item's activeFocus: that moves to a slider or tile inside the panel on a click.
    signal windowFocusLost()

    readonly property bool windowActive: Window.active
    property bool hadWindowFocus: false
    onWindowActiveChanged: {
        if (windowActive) hadWindowFocus = true;
        else if (hadWindowFocus) windowFocusLost();
    }

    // What each tile id shows. The state comes from tileState(), so a binding on it follows the backend.
    readonly property var catalog: ({
        wifi: { text: "Wi-Fi", icon: "wifi", offIcon: "wifi_off", dualTarget: true },
        bluetooth: { text: "Bluetooth", icon: "bluetooth", offIcon: "bluetooth_disabled", dualTarget: true },
        mic: { text: "Microphone", icon: "mic", offIcon: "mic_off" },
        dark: { text: "Dark theme", icon: "contrast", offIcon: "contrast" },
        airplane: { text: "Airplane mode", icon: "flight", offIcon: "flight" }
    })

    function tileState(id) {
        var b = backend;
        if (!b) return { active: false, available: false, secondary: "" };
        switch (id) {
        case "wifi":
            return { active: b.wifiEnabled, available: b.wifiAvailable,
                     secondary: !b.wifiAvailable ? "Unavailable" : !b.wifiEnabled ? "Off" : (b.wifiName || "On") };
        case "bluetooth":
            return { active: b.bluetoothEnabled, available: b.bluetoothAvailable,
                     secondary: !b.bluetoothAvailable ? "Unavailable" : !b.bluetoothEnabled ? "Off" : (b.bluetoothDevice || "On") };
        case "mic":
            return { active: !b.micMuted, available: b.micAvailable,
                     secondary: !b.micAvailable ? "Unavailable" : b.micMuted ? "Muted" : "On" };
        case "dark":
            return { active: b.darkTheme, available: true, secondary: b.darkTheme ? "On" : "Off" };
        case "airplane": {
            const radios = b.wifiAvailable || b.bluetoothAvailable;
            const on = radios && !(b.wifiAvailable && b.wifiEnabled) && !(b.bluetoothAvailable && b.bluetoothEnabled);
            return { active: on, available: radios, secondary: on ? "On" : "Off" };
        }
        }
        return { active: false, available: false, secondary: "" };
    }

    function toggleTile(id, wanted) {
        switch (id) {
        case "wifi": backend.setWifiEnabled(wanted); break;
        case "bluetooth": backend.setBluetoothEnabled(wanted); break;
        case "mic": backend.setMicMuted(!wanted); break;
        case "dark": backend.setDarkTheme(wanted); break;
        case "airplane": backend.setAirplaneMode(wanted); break;
        }
    }

    function choosePower(id) {
        powerMenuOpen = false;
        backend.powerAction(id);
        powerActionTaken(id);
    }

    function removeSelected() {
        if (grid.selectedIndex < 0) return;
        var next = tiles.filter((item, i) => i !== grid.selectedIndex);
        grid.selectedIndex = -1;
        tiles = next;
        tilesEdited(next);
    }

    implicitWidth: panelWidth
    implicitHeight: content.height + 2 * Spacing.lg
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.extraLarge
    color: Colors.surfaceContainer

    // Grows from the corner under the status pill on the spatial spring; the fade uses the effects curve so it
    // does not overshoot. Input is off while it goes away.
    transformOrigin: Item.TopRight
    scale: 0.85 + 0.15 * appear.value
    opacity: shown ? 1 : 0
    Behavior on opacity { EffectsNumber {} }
    enabled: shown
    Spring {
        id: appear
        value: 0        // created at 0 with target 1: it grows in
        target: root.shown ? 1 : 0
        onSettledChanged: if (settled && !root.shown) root.hidden()
    }

    // The backend may arrive after creation (a binding through the window): refresh when it does.
    onBackendChanged: if (backend) backend.refresh()
    Component.onCompleted: if (backend) backend.refresh()

    Column {
        id: content
        x: Spacing.lg
        y: Spacing.lg
        width: parent.width - 2 * Spacing.lg
        spacing: Spacing.md

        // ---- header: edit tiles, settings, power; in edit mode: back, title, remove ----
        Item {
            width: parent.width
            height: ControlSpec.iconButtonSizes.s.height

            Row {
                visible: !root.editMode
                anchors.verticalCenter: parent.verticalCenter
                IconButton {
                    objectName: "qsEditTiles"
                    iconName: "edit"
                    onClicked: root.editMode = true
                }
                IconButton {
                    objectName: "qsSettings"
                    iconName: "settings"
                    onClicked: root.settingsRequested()
                }
            }
            // Googlebook's power button: the power icon and a smaller chevron, opening the menu. Two Icons: one Icon
            // with two ligatures puts the font's wide space between them.
            Rectangle {
                id: powerButton
                objectName: "qsPower"
                visible: !root.editMode
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: powerIcons.width + 2 * Spacing.sm
                height: ControlSpec.iconButtonSizes.s.height
                radius: height / 2
                color: root.powerMenuOpen ? Colors.secondaryContainer : Colors.surfaceContainer
                Behavior on color { EffectsColor {} }
                readonly property color contentColor: root.powerMenuOpen ? Colors.secondaryContainerOn : Colors.surfaceVariantOn
                Row {
                    id: powerIcons
                    anchors.centerIn: parent
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "power_settings_new"
                        size: ControlSpec.iconButtonSizes.s.icon
                        color: powerButton.contentColor
                    }
                    Icon {
                        objectName: "qsPowerChevron"
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.powerMenuOpen ? "expand_less" : "expand_more"
                        size: Spacing.lg
                        color: powerButton.contentColor
                    }
                }
                StateLayer {
                    anchors.fill: parent
                    radius: powerButton.radius
                    stateColor: powerButton.contentColor
                    onClicked: root.powerMenuOpen = !root.powerMenuOpen
                }
            }

            Row {
                visible: root.editMode
                anchors.verticalCenter: parent.verticalCenter
                spacing: Spacing.sm
                IconButton {
                    objectName: "qsEditDone"
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "arrow_back"
                    onClicked: root.editMode = false
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Edit tiles"
                    color: Colors.surfaceOn
                    font: Type.font(Type.titleMedium)
                }
            }
            Button {
                objectName: "qsRemove"
                visible: root.editMode
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Remove"
                type: "filled"
                size: "s"
                enabled: grid.selectedIndex >= 0
                onClicked: root.removeSelected()
            }
        }

        // ---- brightness and volume ----
        Column {
            width: parent.width
            spacing: Spacing.sm
            visible: !root.editMode

            Row {
                id: brightnessRow
                objectName: "qsBrightnessRow"
                visible: root.backend?.brightnessAvailable ?? false
                spacing: Spacing.sm
                Slider {
                    id: brightnessSlider
                    objectName: "qsBrightness"
                    anchors.verticalCenter: parent.verticalCenter
                    width: content.width - darkButton.width - parent.spacing
                    size: "m"
                    endIcon: "brightness_medium"
                    onMoved: v => root.backend.setBrightness(v)
                    Binding on value {
                        value: root.backend?.brightness ?? 0
                        when: !brightnessSlider.pressed
                        restoreMode: Binding.RestoreNone
                    }
                }
                IconButton {
                    id: darkButton
                    objectName: "qsDarkButton"
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "dark_mode"
                    toggle: true
                    checked: root.backend?.darkTheme ?? false
                    onClicked: root.backend.setDarkTheme(!root.backend.darkTheme)
                }
            }

            Row {
                visible: root.backend?.volumeAvailable ?? false
                spacing: Spacing.sm
                Slider {
                    id: volumeSlider
                    objectName: "qsVolume"
                    anchors.verticalCenter: parent.verticalCenter
                    width: content.width - soundButton.width - parent.spacing
                    size: "m"
                    endIcon: root.backend?.muted ? "music_off" : "music_note"
                    onMoved: v => root.backend.setVolume(v)
                    Binding on value {
                        value: root.backend?.muted ? 0 : (root.backend?.volume ?? 0)
                        when: !volumeSlider.pressed
                        restoreMode: Binding.RestoreNone
                    }
                }
                IconButton {
                    id: soundButton
                    objectName: "qsSoundSettings"
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "tune"
                    onClicked: root.soundSettingsRequested()
                }
            }
        }

        // ---- tiles ----
        Rectangle {
            width: parent.width
            height: grid.height + (root.editMode ? 2 * Spacing.sm : 0)
            radius: Shapes.extraLarge
            color: Colors.surfaceContainer
            border.width: root.editMode ? Spacing.xs / 2 : 0
            border.color: Colors.primary

            EditableGrid {
                id: grid
                objectName: "qsGrid"
                x: root.editMode ? Spacing.sm : 0
                y: root.editMode ? Spacing.sm : 0
                width: parent.width - 2 * x
                columns: 4
                items: root.tiles
                slotRadius: ControlSpec.tileSpec.inactiveCornerRadius
                commitHandler: items => {
                    root.tiles = items;
                    root.tilesEdited(items);
                }
                delegate: Tile {
                    id: tile
                    property var modelData: ({})
                    readonly property var info: root.catalog[tile.modelData.id] ?? { text: tile.modelData.id, icon: "help" }
                    readonly property var live: root.tileState(tile.modelData.id)
                    objectName: "qsTile_" + (tile.modelData.id ?? "")
                    controlled: true
                    text: tile.info.text
                    secondaryText: tile.live.secondary
                    iconName: tile.live.active || !tile.info.offIcon ? tile.info.icon : tile.info.offIcon
                    active: tile.live.active
                    available: tile.live.available
                    dualTarget: tile.info.dualTarget ?? false
                    iconOnly: !(tile.modelData.w > 1)
                    onToggled: wanted => root.toggleTile(tile.modelData.id, wanted)
                    onClicked: root.detailsRequested(tile.modelData.id)
                }
            }
        }
    }

    // The power menu over the tiles, under the power button; created only while open (D31).
    Loader {
        objectName: "qsPowerMenu"
        active: root.powerMenuOpen && !root.editMode
        z: 1
        anchors.right: parent.right
        anchors.rightMargin: Spacing.lg
        y: Spacing.lg + ControlSpec.iconButtonSizes.s.height + Spacing.xs
        sourceComponent: PowerMenu {
            onChosen: id => root.choosePower(id)
        }
    }
}
