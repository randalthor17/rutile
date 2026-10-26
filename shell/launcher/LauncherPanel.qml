pragma ComponentBehavior: Bound
// The launcher (plan 2.7): a search field, category chips, and the apps as a grid or a list, ranked by Scorer.js
// as you type. Plain QtQuick on `apps` ([{id, name, icon (URL), genericName, keywords, subtitle, categories}]), so
// it tests offscreen; LauncherWindow.qml gives it the desktop entries. The keyboard stays in the field: the arrows
// move through the results (in the list, Left and Right move the text cursor, as do Home and End), Tab and
// Shift+Tab step through the chips, Enter opens the current app, Escape closes. It grows in and out with the
// shared popup motion (D43), then reports `hidden`.
import QtQuick
import qs.common
import qs.components
import "Scorer.js" as Scorer
import "Categories.js" as Categories

Rectangle {
    id: root

    property var apps: []
    property alias query: field.text
    property string category: ""            // a Categories.js chip id; "" is All
    property bool listView: false           // the toggle sets it; the shell keeps it between openings
    readonly property var categories: Categories.present(apps)
    readonly property var results: Scorer.rank(Categories.filter(apps, category), query)
    readonly property alias currentIndex: grid.currentIndex
    readonly property int columns: 5
    readonly property real cell: Spacing.xxxl * 2 + Spacing.sm
    readonly property real rowHeight: Spacing.xxxl + Spacing.sm
    property bool shown: true

    signal launched(var app)
    signal closeRequested()
    signal hidden()

    // Close when another window takes the keyboard, after having had it (as Quick Settings, D41).
    readonly property bool windowActive: Window.active
    property bool hadWindowFocus: false
    onWindowActiveChanged: {
        if (windowActive) hadWindowFocus = true;
        else if (hadWindowFocus) closeRequested();
    }

    // Tab and Shift+Tab: the next or previous chip, All included, wrapping.
    function stepCategory(delta) {
        const ids = [""].concat(categories.map(c => c.id));
        const at = Math.max(0, ids.indexOf(category));
        category = ids[(at + delta + ids.length) % ids.length];
    }

    function launchCurrent() {
        if (grid.currentIndex >= 0 && grid.currentIndex < results.length) launched(results[grid.currentIndex]);
    }

    implicitWidth: columns * cell + 2 * Spacing.lg
    implicitHeight: content.height + 2 * Spacing.lg
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.extraLarge
    color: Colors.surfaceContainer

    PopupMotion {
        target: root
        shown: root.shown
        origin: Item.Bottom
        onHidden: root.hidden()
    }

    Column {
        id: content
        x: Spacing.lg
        y: Spacing.lg
        width: parent.width - 2 * Spacing.lg
        spacing: Spacing.md

        Rectangle {
            width: parent.width
            height: Spacing.xxxl
            radius: height / 2
            color: Colors.surfaceContainerHigh

            Icon {
                id: searchIcon
                x: Spacing.md
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: Spacing.xl
                color: Colors.surfaceVariantOn
            }
            Text {
                anchors.left: field.left
                anchors.verticalCenter: parent.verticalCenter
                visible: field.text === ""
                text: "Search apps"
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodyLarge)
            }
            TextInput {
                id: field
                objectName: "launcherSearch"
                anchors.left: searchIcon.right
                anchors.leftMargin: Spacing.md
                anchors.right: viewToggle.left
                anchors.rightMargin: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                color: Colors.surfaceOn
                selectionColor: Colors.primary
                selectedTextColor: Colors.primaryOn
                font: Type.font(Type.bodyLarge)
                Keys.onUpPressed: grid.moveCurrentIndexUp()
                Keys.onDownPressed: grid.moveCurrentIndexDown()
                Keys.onLeftPressed: event => {
                    if (root.listView) event.accepted = false;
                    else grid.moveCurrentIndexLeft();
                }
                Keys.onRightPressed: event => {
                    if (root.listView) event.accepted = false;
                    else grid.moveCurrentIndexRight();
                }
                Keys.onTabPressed: root.stepCategory(1)
                Keys.onBacktabPressed: root.stepCategory(-1)
                Keys.onReturnPressed: root.launchCurrent()
                Keys.onEnterPressed: root.launchCurrent()
                Keys.onEscapePressed: root.closeRequested()
            }
            IconButton {
                id: viewToggle
                objectName: "launcherViewToggle"
                anchors.right: parent.right
                anchors.rightMargin: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                size: "s"
                // shows the view a click switches to
                iconName: root.listView ? "grid_view" : "view_list"
                Accessible.name: root.listView ? "Show as grid" : "Show as list"
                onClicked: root.listView = !root.listView
            }
        }

        Flickable {
            id: chips
            objectName: "launcherChips"
            width: parent.width
            height: chipRow.height
            contentWidth: chipRow.width
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            // Keep the chosen chip in view when the keyboard steps past the edge, scrolling with a spring.
            // Choosing one moves the check mark, which grows one chip and shrinks another over a few frames, so
            // reveal each time the row has placed them again (before that the chips' x and the row's width are
            // stale), and stay within the row as it shrinks.
            property Item chosen: null
            function reveal() {
                if (!chosen) return;
                let x = contentX;
                if (chosen.x < x) x = chosen.x;
                else if (chosen.x + chosen.width > x + width) x = chosen.x + chosen.width - width;
                x = Math.max(0, Math.min(x, chipRow.width - width));
                scroll.value = contentX;    // from where it is (the wheel may have moved it), keeping any velocity
                scroll.target = x;
                if (x !== contentX) scroll.settled = false;     // the same target as before still moves
            }
            Spring {
                id: scroll
                stiffness: Motion.spring("spatial", "default").stiffness
                dampingRatio: 1     // no overshoot past the row's ends
                onValueChanged: chips.contentX = value
            }

            Row {
                id: chipRow
                spacing: Spacing.sm
                onPositioningComplete: chips.reveal()
                Repeater {
                    model: [{ id: "", label: "All" }].concat(root.categories)
                    delegate: Chip {
                        id: chip
                        required property var modelData
                        objectName: "launcherChip_" + (modelData.id || "all")
                        type: "filter"
                        controlled: true
                        activeFocusOnTab: false
                        text: modelData.label
                        selected: root.category === chip.modelData.id
                        onSelectedChanged: if (selected) chips.chosen = chip
                        // a click on the chosen chip (other than All) goes back to All
                        onToggled: wanted => root.category = wanted ? chip.modelData.id : ""
                    }
                }
            }
        }

        GridView {
            id: grid
            objectName: "launcherGrid"
            // the results fade and rise in when a chip or the view changes (not while typing)
            opacity: appear.value
            transform: Translate { y: (1 - appear.value) * Spacing.lg }
            Spring {
                id: appear
                value: 1
                target: 1
                stiffness: Motion.spring("effects", "default").stiffness
                dampingRatio: Motion.spring("effects", "default").dampingRatio
            }
            function replay() {
                appear.value = 0;
                appear.settled = false;
            }
            Connections {
                target: root
                function onCategoryChanged() { grid.replay(); }
                function onListViewChanged() { grid.replay(); }
            }
            width: parent.width
            height: 4 * root.cell
            cellWidth: root.listView ? width : root.cell
            cellHeight: root.listView ? root.rowHeight : root.cell
            clip: true
            model: root.results
            // a new result list starts at its best match: GridView resets currentIndex when the model changes
            keyNavigationWraps: false
            boundsBehavior: Flickable.StopAtBounds
            delegate: LauncherTile {
                required property var modelData
                required property int index
                objectName: "launcherApp_" + modelData.id
                width: grid.cellWidth
                height: grid.cellHeight
                row: root.listView
                name: modelData.name
                subtitle: modelData.genericName || modelData.subtitle || ""
                iconSource: modelData.icon || ""
                current: index === grid.currentIndex
                onClicked: root.launched(modelData)
            }

            Text {
                anchors.centerIn: parent
                visible: root.results.length === 0
                text: root.apps.length === 0 ? "No apps found" : "No apps match"
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodyLarge)
            }
        }
    }
}
