// The shelf's pinned apps (plan 5.2): in order, each moved up or down or unpinned, and back to the default (the
// first installed file manager, browser and terminal). Apps are pinned from a right click on the shelf or in the
// launcher. A page view: the app sets `app`, `store` and `backend` (ShelfPinsBackend.qml, or the tests' fake),
// which has managed (set in Nix: nothing changes here), isDefault, pins: [(id, name, icon, installed)],
// setPins(ids), reset(). The group is `setting_shelf.pins` (Pages.js entries).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import "../../shelf/ShelfApps.js" as ShelfApps

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    readonly property var pins: backend?.pins ?? []
    readonly property bool managed: backend?.managed ?? false
    readonly property var ids: pins.map(p => p.id)

    function segment(i, n) {
        return app ? app.segment(i, n) : "single";
    }

    spacing: Spacing.xl

    ListItem {
        objectName: "shelfManaged"
        visible: page.managed
        width: page.width
        iconName: "lock"
        text: "Set in your Nix configuration"
        supportingText: "programs.rutile.settings.shelf.pins"
    }

    Column {
        objectName: "setting_shelf.pins"
        width: page.width
        spacing: ControlSpec.listSpec.segmentedGap
        Text {
            height: implicitHeight + Spacing.sm
            leftPadding: Spacing.lg
            text: "Pinned apps"
            color: Colors.primary
            font: Type.font(Type.titleSmall)
        }
        ListItem {
            objectName: "shelfNoPins"
            visible: page.pins.length === 0
            width: page.width
            text: "No pinned apps"
            enabled: false
        }
        Repeater {
            model: page.pins
            delegate: ListItem {
                id: pin
                required property var modelData
                required property int index
                objectName: "shelfPinRow_" + index
                width: page.width
                position: page.segment(index, page.pins.length)
                tone: Colors.surfaceContainer
                iconSource: modelData.icon
                iconName: modelData.icon === "" ? "apps" : ""
                text: modelData.name
                supportingText: modelData.installed ? "" : "Not installed"
                Row {
                    visible: !page.managed
                    spacing: Spacing.xs
                    IconButton {
                        objectName: "shelfPinUp_" + pin.index
                        iconName: "arrow_upward"
                        enabled: pin.index > 0
                        Accessible.name: "Move " + pin.modelData.name + " earlier"
                        onClicked: page.backend.setPins(ShelfApps.move(page.ids, pin.index, -1))
                    }
                    IconButton {
                        objectName: "shelfPinDown_" + pin.index
                        iconName: "arrow_downward"
                        enabled: pin.index < page.pins.length - 1
                        Accessible.name: "Move " + pin.modelData.name + " later"
                        onClicked: page.backend.setPins(ShelfApps.move(page.ids, pin.index, 1))
                    }
                    IconButton {
                        objectName: "shelfPinRemove_" + pin.index
                        iconName: "keep_off"
                        Accessible.name: "Unpin " + pin.modelData.name
                        onClicked: page.backend.setPins(page.ids.filter((_, i) => i !== pin.index))
                    }
                }
            }
        }
    }

    Column {
        width: page.width
        spacing: ControlSpec.listSpec.segmentedGap
        ListItem {
            width: page.width
            position: page.managed ? "single" : "first"
            tone: Colors.surfaceContainer
            iconName: "keep"
            text: "Pin more apps"
            supportingText: "Right click an app on the shelf or in the launcher, and choose Pin"
            enabled: false
        }
        ListItem {
            objectName: "shelfPinsReset"
            visible: !page.managed
            width: page.width
            position: "last"
            tone: Colors.surfaceContainer
            iconName: "restart_alt"
            text: "Back to the default"
            supportingText: "The first installed file manager, browser and terminal"
            enabled: !(page.backend?.isDefault ?? true)
            onClicked: page.backend.reset()
        }
    }
}
