pragma ComponentBehavior: Bound
// The shelf (plan 2.4): a bar along the bottom with the launcher button at its left, and in the middle the pinned
// apps (a dot under one with a window open; dragged sideways to reorder them, `pinsReordered`) and, after a divider,
// the open windows grouped by workspace: a capsule per workspace with its number and one icon per window, the
// active workspace's capsule tinted, the focused window marked (as Noctalia's taskbar groups them). The wheel over
// the shelf moves between workspaces, one per notch (touchpads add up to a notch). Plain QtQuick
// on data from ShelfApps.js (icons as URLs), so it tests offscreen; ShelfWindow.qml gives it the real ones.
// Above each end a concave corner (`cornerRadius` tall, drawn outside the bar) joins it to the screen's side, as
// rounded screen corners rising out of it (D115); the bar and corners are as see-through as the panels.
import QtQuick
import QtQuick.Shapes
import qs.common
import qs.components
import "ShelfApps.js" as ShelfApps

Rectangle {
    id: root

    property var pinned: []         // [{id, name, icon, running}]
    property bool pinsMovable: true // false while Nix sets the pins (D45)
    property var groups: []         // ShelfApps.decorate() / ungrouped()

    signal launched(var app)
    signal pinsReordered(var ids)           // the pins' ids in their new order, after a drag
    signal windowClicked(var window)
    signal launcherClicked()
    signal workspaceScrolled(int delta)     // +1: the next workspace (down), -1: the previous
    // a right click: `target` is {app} for a pin or {window} for a window, `x` the button's middle on the shelf
    signal menuRequested(var target, real x)

    // The tooltip of the button under the pointer (D106): its text and middle on the shelf; "" for none. It comes after
    // `tooltipDelay` of hovering, at once when the pointer moves on from a button whose tooltip shows, and goes when
    // the pointer leaves the buttons or presses one.
    property string tooltipText: ""
    property real tooltipX: 0
    property int tooltipDelay: 500
    property Item hoveredButton: null
    function hover(button) {
        if (button.hovered) {
            hoveredButton = button;
            if (tooltipText !== "") showTooltip();
            else tooltipWait.restart();
        } else if (hoveredButton === button) {
            hoveredButton = null;
            tooltipWait.stop();
            // a move to the next button leaves this one first: hide only if none is entered meanwhile
            Qt.callLater(() => { if (!root.hoveredButton) root.tooltipText = ""; });
        }
    }
    function showTooltip() {
        if (!hoveredButton) return;
        tooltipText = hoveredButton.tooltip;
        tooltipX = hoveredButton.mapToItem(root, hoveredButton.width / 2, 0).x;
    }
    function hideTooltip() {
        tooltipWait.stop();
        tooltipText = "";
    }
    Timer {
        id: tooltipWait
        interval: root.tooltipDelay
        onTriggered: root.showTooltip()
    }

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

    implicitHeight: Spacing.xxxl
    height: implicitHeight
    color: Panels.tint(Colors.surfaceContainerLowest)
    readonly property real cornerRadius: Shapes.large
    readonly property real launcherX: Spacing.md     // where the launcher button is: the launcher opens above it

    // The two corners: each fills between the screen's side, the bar's top and a quarter circle.
    Repeater {
        model: 2
        Shape {
            id: corner
            required property int index
            objectName: "shelfCorner_" + (index === 0 ? "left" : "right")
            readonly property real r: root.cornerRadius
            width: r
            height: r
            y: -r
            x: index === 0 ? 0 : root.width - r
            transform: Scale { origin.x: root.cornerRadius / 2; xScale: corner.index === 0 ? 1 : -1 }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillColor: root.color
                startX: 0; startY: 0
                PathLine { x: 0; y: root.cornerRadius }
                PathLine { x: root.cornerRadius; y: root.cornerRadius }
                PathArc { x: 0; y: 0; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
            }
        }
    }

    signal pressed()                        // a press on the shelf between its buttons (the shell closes its popups, D90)
    MouseArea {
        objectName: "shelfBackground"
        anchors.fill: parent
        onPressed: root.pressed()
    }

    // The launcher (plan 2.7), at the left. Googlebook's is a "G" pill; Rutile's shows the apps icon.
    Rectangle {
        objectName: "shelfLauncher"
        anchors.verticalCenter: parent.verticalCenter
        x: root.launcherX
        width: Spacing.xxxl + Spacing.sm
        height: Spacing.xxl
        radius: height / 2
        color: Colors.surfaceContainerHigh
        Icon {
            anchors.centerIn: parent
            name: "apps"
            size: Spacing.lg + Spacing.xs
            color: Colors.surfaceOn
        }
        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            stateColor: Colors.surfaceOn
            onClicked: root.launcherClicked()
        }
    }

    // A pin dragged sideways: the others step aside, and on release the new order is asked for.
    property int dragFrom: -1
    property int dragTo: -1
    function dropPin() {
        const from = dragFrom, to = dragTo;
        dragFrom = dragTo = -1;
        if (from < 0 || to === from) return;
        const ids = pinned.map(p => p.id);
        const it = ids.splice(from, 1)[0];
        ids.splice(to, 0, it);
        pinsReordered(ids);
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Spacing.sm

        Repeater {
            model: root.pinned
            ShelfButton {
                id: pin
                required property var modelData
                required property int index
                readonly property real slot: width + row.spacing
                objectName: "shelfPin_" + modelData.id
                name: modelData.name
                iconSource: modelData.icon
                running: modelData.running === true
                z: drag.active ? 1 : 0
                // the others step aside smoothly; the dragged one follows the pointer
                property real shift: ShelfApps.dragShift(index, root.dragFrom, root.dragTo) * slot
                Behavior on shift { EffectsNumber {} }
                transform: Translate { x: drag.active ? drag.dx : pin.shift }
                DragHandler {
                    id: drag
                    property real dx: 0
                    target: null
                    enabled: root.pinsMovable && root.pinned.length > 1
                    yAxis.enabled: false
                    onTranslationChanged: {
                        dx = translation.x;
                        if (active) root.dragTo = ShelfApps.dropIndex(pin.index, dx, pin.slot, root.pinned.length);
                    }
                    onActiveChanged: {
                        if (active) {
                            root.hideTooltip();
                            root.dragFrom = root.dragTo = pin.index;
                        } else {
                            root.dropPin();
                            dx = 0;
                        }
                    }
                }
                onHoveredChanged: root.hover(pin)
                onClicked: {
                    root.hideTooltip();
                    root.launched(modelData);
                }
                onMenuRequested: {
                    root.hideTooltip();
                    root.menuRequested({ app: modelData }, mapToItem(root, width / 2, 0).x);
                }
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
                height: Spacing.xxl + Spacing.sm
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
                            id: windowButton
                            required property var modelData
                            objectName: "shelfWindow_" + modelData.id
                            name: modelData.name
                            tooltip: modelData.title || modelData.name
                            iconSource: modelData.icon
                            running: modelData.focused
                            active: modelData.focused
                            onHoveredChanged: root.hover(windowButton)
                            onClicked: {
                                root.hideTooltip();
                                root.windowClicked(modelData);
                            }
                            onMenuRequested: {
                                root.hideTooltip();
                                root.menuRequested({ window: modelData }, mapToItem(root, width / 2, 0).x);
                            }
                        }
                    }
                }
            }
        }
    }
}
