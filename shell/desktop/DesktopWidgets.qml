// One screen's desktop widgets (plan 4.4, D81): placed widgets on the shared EditableGrid (1.6), with gravity off
// so each stays where it was put. Cells are square, `columns` across the screen. In `editMode` widgets are moved and
// resized as Quick Settings tiles are, and a bar at the bottom adds a widget (from `available`), removes the selected
// one, moves it to another screen (`screens`, when there are others), and finishes (Escape too; Delete removes). Plain QtQuick: files are read by the owner, which hands over
// `specs` (path: spec, or null when the file cannot be read) and saves what `commitHandler` gets.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import "Desktop.js" as Desktop

Item {
    id: root

    property var items: []
    property var specs: ({})
    property var available: []             // [{path, name}], what Add offers
    property bool editMode: false
    property int columns: 12
    property bool scaleText: false         // text follows a widget's size (widgets.scaleText, D84)
    property var commitHandler: null       // a callback, as EditableGrid's: the whole list after each change
    property var screens: []               // [{name, label}], the other screens a widget can be moved to
    property var roomOn: null              // (screen name, item): the size it gets there, or null when it is full
    readonly property alias grid: desktopGrid
    // where the widgets are, in this item: outside edit mode the window takes the pointer only there (D86)
    readonly property var inputRects: desktopGrid.slotLayout.slots.filter(s => !!s)
        .map(s => ({ x: desktopGrid.x + s.x, y: desktopGrid.y + s.y, width: s.w, height: s.h }))
    // Starts editing with widget `index` selected (a right-click on it).
    function select(index) {
        desktopGrid.selectedIndex = index;
    }
    readonly property bool addOpen: addMenu.open
    readonly property bool moveOpen: moveMenu.open

    signal doneRequested()
    signal addListRequested()              // Add was opened: the owner lists the widget files again
    signal galleryRequested()              // "More widgets": the Widgets app
    signal editRequested(int index)        // a widget was right-clicked: edit, with it selected
    signal pressed()                        // a widget was pressed (the shell closes its popups, D90)
    signal moveRequested(int index, string screen)   // move widget `index` to that screen; the owner saves both

    function commit(next) {
        if (commitHandler)
            commitHandler(next);
        else
            items = next;
    }
    // Places the widget file `path` in the first free cells; false when the screen has no room for it.
    function add(path) {
        const size = desktopGrid.fitNew(Desktop.NEW_SIZE);
        if (!size)
            return false;
        const next = Desktop.withAdded(items, path, size);
        commit(next);
        // selected once the grid has it, so it can be moved and sized at once
        Qt.callLater(() => desktopGrid.selectedIndex = next.length - 1);
        return true;
    }
    function removeSelected() {
        if (desktopGrid.selectedIndex < 0 || desktopGrid.selectedIndex >= items.length)
            return false;
        const index = desktopGrid.selectedIndex;
        desktopGrid.selectedIndex = -1;
        commit(Desktop.withoutIndex(items, index));
        return true;
    }

    focus: editMode
    Keys.onEscapePressed: {
        if (addMenu.open || moveMenu.open) {
            addMenu.open = false;
            moveMenu.open = false;
        } else
            root.doneRequested();
    }
    Keys.onDeletePressed: root.removeSelected()
    onEditModeChanged: if (!editMode) {
        addMenu.open = false;
        moveMenu.open = false;
    }

    // Over the whole screen while editing, so the widgets stand out from the wallpaper and a click on empty space
    // drops the selection.
    Rectangle {
        anchors.fill: parent
        visible: root.editMode
        color: Qt.alpha(Colors.scrim, ControlSpec.stateOpacity.dragged)
        MouseArea {
            anchors.fill: parent
            enabled: root.editMode
            onClicked: {
                addMenu.open = false;
                moveMenu.open = false;
                desktopGrid.selectedIndex = -1;
            }
        }
    }

    EditableGrid {
        id: desktopGrid
        objectName: "desktopGrid"
        anchors.fill: parent
        anchors.margins: Spacing.xl     // the same in edit mode, so nothing moves when it starts; the bar floats over
        columns: root.columns
        rowHeight: (width - gap * (columns - 1)) / Math.max(1, columns)
        gap: Spacing.lg
        // from the screen, not the grid's own height, which follows its rows
        maxRows: Math.max(1, Math.floor((root.height - 2 * anchors.margins + gap) / (rowHeight + gap)))
        gravity: false
        editMode: root.editMode
        items: root.items
        commitHandler: next => root.commit(next)
        delegate: DesktopWidget {
            specs: root.specs
            scaleText: root.scaleText
            // a new widget's cells (Desktop.NEW_SIZE): text is drawn at its size there
            base: Qt.size(Desktop.NEW_SIZE.w * desktopGrid.rowHeight + (Desktop.NEW_SIZE.w - 1) * desktopGrid.gap,
                          Desktop.NEW_SIZE.h * desktopGrid.rowHeight + (Desktop.NEW_SIZE.h - 1) * desktopGrid.gap)
            editMode: root.editMode
            onEditRequested: index => root.editRequested(index)
            onPressed: root.pressed()
        }
    }

    // The edit bar, only while editing.
    Rectangle {
        id: bar
        objectName: "desktopEditBar"
        z: 2
        visible: root.editMode
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - height - Spacing.xl
        width: buttons.implicitWidth + 2 * Spacing.sm
        height: buttons.implicitHeight + 2 * Spacing.sm
        radius: height / 2
        color: Colors.surfaceContainerHigh
        Row {
            id: buttons
            anchors.centerIn: parent
            spacing: Spacing.sm
            Button {
                objectName: "desktopAdd"
                type: "tonal"
                iconName: "add"
                text: "Add widget"
                onClicked: {
                    moveMenu.open = false;
                    addMenu.open = !addMenu.open;
                    if (addMenu.open)
                        root.addListRequested();
                }
            }
            Button {
                objectName: "desktopRemove"
                type: "tonal"
                iconName: "delete"
                text: "Remove"
                enabled: desktopGrid.selectedIndex >= 0
                onClicked: root.removeSelected()
            }
            Button {
                id: moveButton
                objectName: "desktopMove"
                type: "tonal"
                iconName: "move_item"
                text: "Move to"
                visible: root.screens.length > 0
                enabled: desktopGrid.selectedIndex >= 0
                onEnabledChanged: if (!enabled) moveMenu.open = false
                onClicked: {
                    addMenu.open = false;
                    moveMenu.open = !moveMenu.open;
                }
            }
            Button {
                objectName: "desktopDone"
                iconName: "check"
                text: "Done"
                onClicked: root.doneRequested()
            }
        }
    }

    PopupLoader {
        id: addMenu
        z: 3
        origin: Item.Bottom
        x: bar.x
        y: bar.y - ((item as Item)?.height ?? 0) - Spacing.sm
        sourceComponent: Menu {
            readonly property bool room: desktopGrid.fitNew(Desktop.NEW_SIZE) !== null
            items: (root.available.length === 0
                    ? [{ id: "none", text: "No widgets found", icon: "", enabled: false }]
                    : root.available.map((a, i) => ({ id: String(i), text: a.name, icon: "widgets", enabled: room })))
                   .concat([{ separator: true }, { id: "gallery", text: "More widgets…", icon: "apps" }])
            itemPrefix: "desktopAddItem_"
            onChosen: id => {
                addMenu.open = false;
                if (id === "gallery") {
                    root.galleryRequested();
                    return;
                }
                const entry = root.available[Number(id)];
                if (entry)
                    root.add(entry.path);
            }
        }
    }

    // The other screens, each greyed out when the selected widget has no room there.
    PopupLoader {
        id: moveMenu
        z: 3
        origin: Item.Bottom
        x: bar.x + moveButton.x + buttons.x
        y: bar.y - ((item as Item)?.height ?? 0) - Spacing.sm
        sourceComponent: Menu {
            readonly property var widget: root.items[desktopGrid.selectedIndex] ?? null
            items: root.screens.map(s => ({ id: s.name, text: s.label, icon: "monitor",
                                            enabled: !!widget && (!root.roomOn || root.roomOn(s.name, widget) !== null) }))
            itemPrefix: "desktopMoveItem_"
            onChosen: id => {
                moveMenu.open = false;
                const index = desktopGrid.selectedIndex;
                if (index < 0)
                    return;
                desktopGrid.selectedIndex = -1;
                root.moveRequested(index, id);
            }
        }
    }
}
