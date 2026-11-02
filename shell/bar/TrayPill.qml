pragma ComponentBehavior: Bound
// App indicators (plan 2.10, the maintainer's request; D61): the icons apps put in the tray (StatusNotifierItem:
// Discord, Steam, Nextcloud), in a pill between the notification bell and the status pill. It is there only while
// an item shows (TrayModel.shown), and takes no room otherwise. A click activates the app (or opens its menu, for an
// item that only has one), a right click opens its menu, a middle click is the app's secondary action, the wheel
// scrolls it. An item asking for attention gets a dot. Plain QtQuick on `items` ([{id, title, icon, attention,
// item}], `item` the SystemTrayItem), so it tests offscreen; the window opens the menu.
import QtQuick
import qs.common
import qs.components

Rectangle {
    id: root

    property var items: []
    property string openId: ""                  // the item whose menu is open: tinted

    // the item, and where its icon is (x of its right edge, in the pill)
    signal menuRequested(var entry, real right)

    readonly property bool shown: items.length > 0

    visible: shown
    implicitWidth: shown ? row.width + 2 * Spacing.xs : 0
    implicitHeight: Spacing.xl
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: Colors.surfaceContainer

    // The right edge of an item's icon, in the pill (-1: not shown): where its menu goes.
    function rightOf(id) {
        for (let i = 0; i < slots.count; i++) {
            const s = slots.itemAt(i);
            if (s?.objectName === "trayItem_" + id) return row.x + s.x + s.width;
        }
        return -1;
    }

    function press(entry, button, right) {
        const it = entry.item;
        if (button === Qt.RightButton) {
            if (it.hasMenu) root.menuRequested(entry, right);
        } else if (button === Qt.MiddleButton) {
            it.secondaryActivate();
        } else if (it.onlyMenu && it.hasMenu) {
            root.menuRequested(entry, right);
        } else {
            it.activate();
        }
    }

    Row {
        id: row
        x: Spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            id: slots
            model: root.items
            delegate: Item {
                id: slot
                required property var modelData
                objectName: "trayItem_" + modelData.id
                readonly property bool open: root.openId === modelData.id
                width: Spacing.xl - Spacing.xs
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: slot.open ? Colors.secondaryContainer : "transparent"
                    Behavior on color { EffectsColor {} }
                }
                Image {
                    objectName: "trayIcon"
                    anchors.centerIn: parent
                    width: Spacing.lg
                    height: Spacing.lg
                    sourceSize.width: width
                    sourceSize.height: height
                    source: slot.modelData.icon
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Rectangle {
                    objectName: "trayAttention"
                    visible: slot.modelData.attention
                    width: Spacing.xs + Spacing.xs / 2
                    height: width
                    radius: width / 2
                    x: parent.width - width - 1
                    y: 1
                    color: Colors.error
                }
                StateLayer {
                    anchors.fill: parent
                    radius: width / 2
                    stateColor: Colors.surfaceOn
                    input: area
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => root.press(slot.modelData, mouse.button, root.rightOf(slot.modelData.id))
                    onWheel: wheel => {
                        const horizontal = wheel.angleDelta.x !== 0 && wheel.angleDelta.y === 0;
                        slot.modelData.item.scroll(horizontal ? wheel.angleDelta.x : wheel.angleDelta.y, horizontal);
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: slot.modelData.title
            }
        }
    }
}
