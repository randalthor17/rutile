pragma ComponentBehavior: Bound
// The shelf (plan 2.4) as Googlebook shows it: a bar along the bottom with the launcher button, the pinned apps,
// and, after a divider, apps that run without being pinned. Plain QtQuick on `items` from ShelfApps.build() (with
// an icon URL each), so it tests offscreen; ShelfWindow.qml gives it the real apps.
import QtQuick
import qs.common
import qs.components

Rectangle {
    id: root

    property var items: []
    readonly property var pinnedItems: items.filter(it => it.pinned)
    readonly property var otherItems: items.filter(it => !it.pinned)

    signal opened(var item)
    signal launcherClicked()

    implicitHeight: Spacing.xxxl + Spacing.sm
    height: implicitHeight
    color: Colors.surfaceContainerLowest

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Spacing.sm

        // The launcher (plan 2.7). Googlebook's is a "G" pill; Rutile's shows the apps icon.
        Rectangle {
            objectName: "shelfLauncher"
            anchors.verticalCenter: parent.verticalCenter
            width: Spacing.xxxl + Spacing.lg
            height: Spacing.xxl + Spacing.sm
            radius: height / 2
            color: Colors.surfaceContainerHigh
            Icon {
                anchors.centerIn: parent
                name: "apps"
                size: Spacing.xl
                color: Colors.surfaceOn
            }
            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                stateColor: Colors.surfaceOn
                onClicked: root.launcherClicked()
            }
        }

        Repeater {
            model: root.pinnedItems
            ShelfButton {
                required property var modelData
                objectName: "shelfApp_" + modelData.id
                name: modelData.name
                iconSource: modelData.icon
                running: modelData.running
                active: modelData.active
                onClicked: root.opened(modelData)
            }
        }

        Rectangle {
            objectName: "shelfDivider"
            anchors.verticalCenter: parent.verticalCenter
            visible: root.otherItems.length > 0
            width: 1
            height: Spacing.xl
            color: Colors.outlineVariant
        }

        Repeater {
            model: root.otherItems
            ShelfButton {
                required property var modelData
                objectName: "shelfApp_" + modelData.id
                name: modelData.name
                iconSource: modelData.icon
                running: modelData.running
                active: modelData.active
                onClicked: root.opened(modelData)
            }
        }
    }
}
