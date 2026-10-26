pragma ComponentBehavior: Bound
// The shelf (plan 2.4): a bar along the bottom with the launcher button, the pinned apps, and, after a divider,
// the open windows grouped by workspace: a capsule per workspace with its number and one icon per window, the
// active workspace's capsule tinted, the focused window marked (as Noctalia's taskbar groups them). The wheel over
// the shelf moves between workspaces, one per notch (touchpads add up to a notch). Plain QtQuick
// on data from ShelfApps.js (icons as URLs), so it tests offscreen; ShelfWindow.qml gives it the real ones.
import QtQuick
import qs.common
import qs.components

Rectangle {
    id: root

    property var pinned: []         // [{id, name, icon}]
    property var groups: []         // ShelfApps.decorate() / ungrouped()

    signal launched(var app)
    signal windowClicked(var window)
    signal launcherClicked()
    signal workspaceScrolled(int delta)     // +1: the next workspace (down), -1: the previous

    // Wheel deltas add up until a notch (120), so a touchpad's small steps move one workspace at a time.
    property real wheelRest: 0
    function scrollBy(angleDeltaY) {
        wheelRest += angleDeltaY;
        while (Math.abs(wheelRest) >= 120) {
            const up = wheelRest > 0;
            wheelRest -= up ? 120 : -120;
            workspaceScrolled(up ? -1 : 1);
        }
    }
    WheelHandler {
        objectName: "shelfWheel"
        // Qt's Wayland plugin may report a wheel as a touchpad; the default is Mouse only (LESSONS).
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => root.scrollBy(event.angleDelta.y)
    }

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
            model: root.pinned
            ShelfButton {
                required property var modelData
                objectName: "shelfPin_" + modelData.id
                name: modelData.name
                iconSource: modelData.icon
                onClicked: root.launched(modelData)
            }
        }

        Rectangle {
            objectName: "shelfDivider"
            anchors.verticalCenter: parent.verticalCenter
            visible: root.groups.length > 0
            width: 1
            height: Spacing.xl
            color: Colors.outlineVariant
        }

        Repeater {
            model: root.groups
            Rectangle {
                id: group
                required property var modelData
                objectName: "shelfWorkspace_" + modelData.idx
                anchors.verticalCenter: parent.verticalCenter
                width: groupRow.width + 2 * Spacing.xs
                height: Spacing.xxxl
                radius: height / 2
                color: modelData.active ? Colors.secondaryContainer : Colors.surfaceContainer
                Behavior on color { EffectsColor {} }

                Row {
                    id: groupRow
                    x: Spacing.xs
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        objectName: "shelfWorkspaceLabel"
                        visible: group.modelData.idx > 0
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: Spacing.sm
                        rightPadding: Spacing.xs
                        text: group.modelData.name || String(group.modelData.idx)
                        color: group.modelData.active ? Colors.secondaryContainerOn : Colors.surfaceVariantOn
                        font: Type.font(Type.labelLarge)
                    }
                    Repeater {
                        model: group.modelData.windows
                        ShelfButton {
                            required property var modelData
                            objectName: "shelfWindow_" + modelData.id
                            name: modelData.name
                            iconSource: modelData.icon
                            running: modelData.focused
                            active: modelData.focused
                            onClicked: root.windowClicked(modelData)
                        }
                    }
                }
            }
        }
    }
}
