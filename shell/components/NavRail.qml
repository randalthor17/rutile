pragma ComponentBehavior: Bound
// An M3 Expressive navigation rail, collapsed (plan 1.5, D103), from the Compose rail tokens (ControlSpec.navRailSpec):
// a column of destinations, each an icon in a pill-shaped indicator over its label. `items` are
// [{id, text, icon}]; the one whose id is `currentId` is active: its indicator in the secondary container color grows
// out from its middle (the fast spatial spring, D43) and its icon fills. A click, or Enter or Space on a focused item,
// reports `chosen(id)`; the owner sets `currentId` (the rail never changes it itself). Whatever goes in the default
// slot (a menu button, a FAB) sits at the top, above the destinations. `narrow` is the 80 px rail.
import QtQuick
import qs.common

Rectangle {
    id: root

    property var items: []                  // [{id, text, icon}]
    property string currentId: ""
    property bool narrow: false
    readonly property var spec: ControlSpec.navRailSpec
    default property alias header: headerContent.data

    signal chosen(string id)

    implicitWidth: narrow ? spec.collapsed.narrowContainerWidth : spec.collapsed.containerWidth
    implicitHeight: column.y + column.height + Spacing.lg
    color: Colors[spec.collapsed.containerColor]
    radius: spec.collapsed.containerShape

    Column {
        id: column
        width: parent.width
        y: Spacing.lg
        spacing: root.spec.collapsed.itemVerticalSpace

        // the header, centred; the rail's width even when empty, as a Column skips an item with no width
        Item {
            width: column.width
            // the first destination starts the rail's top space down, or below a taller header
            height: Math.max(root.spec.collapsed.topSpace - Spacing.lg - column.spacing, headerContent.height + Spacing.lg)
            Item {
                id: headerContent
                anchors.horizontalCenter: parent.horizontalCenter
                width: childrenRect.width
                height: childrenRect.height
            }
        }

        Repeater {
            model: root.items
            delegate: Item {
                id: item
                required property var modelData
                required property int index
                readonly property bool active: modelData.id === root.currentId
                readonly property var colors: root.spec.colors
                objectName: "navRail_" + modelData.id
                width: column.width
                height: indicator.height + root.spec.item.iconLabelSpace + label.height
                activeFocusOnTab: true
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.text
                Accessible.selected: active
                Keys.onSpacePressed: root.chosen(modelData.id)
                Keys.onReturnPressed: root.chosen(modelData.id)

                // the active indicator, grown from the middle as the item becomes active
                Spring {
                    id: grow
                    target: item.active ? 1 : 0
                    stiffness: Motion.spring("spatial", "fast").stiffness
                    dampingRatio: Motion.spring("spatial", "fast").dampingRatio
                }
                Component.onCompleted: grow.rest()          // shown as it is at first, not grown in
                Item {
                    id: indicator
                    objectName: "navRailIndicator"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.spec.item.activeIndicatorWidth
                    height: root.spec.item.activeIndicatorHeight
                    Rectangle {
                        objectName: "navRailPill"
                        anchors.centerIn: parent
                        width: parent.width * Math.max(0, grow.value)
                        height: parent.height
                        radius: height / 2
                        visible: width > 0
                        color: Colors[item.colors.itemActiveIndicatorColor]
                    }
                    StateLayer {
                        anchors.fill: parent
                        radius: height / 2
                        input: area
                        focused: item.activeFocus
                        stateColor: Colors[item.active ? item.colors.itemActiveHoveredStateLayerColor
                                                       : item.colors.itemInactiveHoveredStateLayerColor]
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: item.modelData.icon ?? ""
                        fill: item.active ? 1 : 0
                        color: Colors[item.active ? item.colors.itemActiveIconColor : item.colors.itemInactiveIconColor]
                    }
                }
                Text {
                    id: label
                    objectName: "navRailLabel"
                    anchors.top: indicator.bottom
                    anchors.topMargin: root.spec.item.iconLabelSpace
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 2 * Spacing.xs
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: item.modelData.text ?? ""
                    color: Colors[item.active ? item.colors.itemActiveLabelTextColor : item.colors.itemInactiveLabelTextColor]
                    font: Type.font(Type[root.spec.item.labelTextFont])
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chosen(item.modelData.id)
                }
            }
        }
    }
}
