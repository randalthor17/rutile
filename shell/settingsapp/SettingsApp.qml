// The settings app's contents (plan 5.1), as Googlebook's Settings: a sidebar with a search field and the pages
// (Pages.js) as a list with tonal icon circles, and the chosen page on the right: its title and its settings in
// segmented groups (SettingRow), an Advanced group last. Typing in the search field lists matching pages and
// settings instead (Model.search); choosing one opens its page and rings the setting, the ring fading after a
// moment (the launcher's settings results open it the same way). Narrower than
// `narrowWidth`, only one side shows: the list, or the page with a back button.
// `store` is the Settings service, or anything with value(key), set(key, value), isManaged(key) and configDir (the
// tests' fake). A path setting asks for a file (`pathRequested`); the window has the file chooser, and runs an action
// (`actionRequested`). Plain QtQuick, so it tests offscreen; SettingsWindow puts it in a window.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import "Model.js" as Model
import "Pages.js" as Pages
import "../services/SettingsSchema.js" as Schema

Rectangle {
    id: root

    required property var store
    property string currentPage: Pages.pages[0].id
    property string highlightKey: ""
    property string menuKey: ""                     // the setting whose choices are open
    property var menuRow: null                      // its SettingRow (kept while the menu closes)
    property bool pageShown: false                  // narrow only: the page instead of the list
    readonly property real narrowWidth: 720
    readonly property bool narrow: width < narrowWidth
    readonly property string query: searchInput.text
    readonly property bool searching: query.trim() !== ""
    readonly property var page: Pages.page(currentPage)
    readonly property var sections: Model.sections(page, Schema.schema, Pages.hints)
    readonly property var results: Model.search(query, Pages.pages, Schema.schema, Pages.hints)
    readonly property alias search: searchInput
    // the open page's backend (Pages.js `backend`), which the window loads; null for the others
    property var backend: null
    // what notices show on (Pages.js `when`): {niriNotIncluded} from the window
    property var conditions: ({})
    readonly property alias pageView: pageView

    signal pathRequested(string key, var filters)
    signal actionRequested(string key)

    // Opens a page (and marks one of its settings); false for an unknown page.
    function openPage(id, key) {
        if (!Pages.page(id)) return false;
        menuKey = "";
        currentPage = id;
        highlightKey = key ?? "";
        searchInput.text = "";
        pageShown = true;
        ring.target = null;
        if (highlightKey !== "") {
            unmark.restart();
            Qt.callLater(scrollToHighlight);
        } else {
            pageFlick.contentY = 0;
        }
        return true;
    }
    function scrollToHighlight() {
        const row = findRow(highlightKey);
        if (!row) return;
        // a new page's rows are placed at the next polish; place them now to measure
        row.parent.forceLayout();
        pageColumn.forceLayout();
        const y = row.mapToItem(pageColumn, 0, 0).y;
        pageFlick.contentY = Math.max(0, Math.min(y - Spacing.xl, pageFlick.contentHeight - pageFlick.height));
        ring.show(row);
    }
    function findRow(key) {
        const stack = [pageColumn];
        while (stack.length) {
            const it = stack.pop();
            if (it.objectName === "setting_" + key) return it;
            for (const c of it.children) stack.push(c);
        }
        return null;
    }
    // Opens a row's choices in the choice dialog, or closes it.
    function toggleMenu(row) {
        if (menuKey === row.row.key) {
            menuKey = "";
            return;
        }
        menuRow = row;
        menuKey = row.row.key;
    }
    // a setting's row saves the choice; a page's own row (ChoiceRow) is told and does the rest
    function choose(index) {
        const r = menuRow;
        menuKey = "";
        if (!r) return;
        if (typeof r.choose === "function") r.choose(index);
        else store.set(r.row.key, r.row.choices[index]);
    }
    function segment(i, n) {
        return n === 1 ? "single" : i === 0 ? "first" : i === n - 1 ? "last" : "middle";
    }

    color: Colors.surfaceContainerLow

    Timer {
        id: unmark
        interval: 2000
        onTriggered: {
            root.highlightKey = "";
            ring.fade();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            root.pageShown = false;                 // narrow: the search is on the list's side
            searchInput.forceActiveFocus();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.menuKey !== "") {
            root.menuKey = "";
            event.accepted = true;
        }
    }

    // ---- the sidebar: search and the pages, or the results ----
    Item {
        id: sidebar
        visible: !root.narrow || !root.pageShown
        width: root.narrow ? root.width : 360
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left

        Rectangle {
            id: searchPill
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Spacing.lg
            height: 56
            radius: Shapes.full
            color: Colors.surfaceContainerLowest
            border.width: searchInput.activeFocus ? 2 : 1
            border.color: searchInput.activeFocus ? Colors.primary : Colors.outlineVariant

            Icon {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: Spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                color: Colors.surfaceVariantOn
            }
            TextInput {
                id: searchInput
                objectName: "settingsSearch"
                anchors.left: searchIcon.right
                anchors.leftMargin: Spacing.md
                anchors.right: clearSearch.left
                anchors.rightMargin: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: Colors.surfaceOn
                selectionColor: Colors.primary
                selectedTextColor: Colors.primaryOn
                font: Type.font(Type.bodyLarge)
                Keys.onEscapePressed: text = ""
                Keys.onReturnPressed: if (root.results.length) root.openPage(root.results[0].page, root.results[0].key)
                Keys.onEnterPressed: if (root.results.length) root.openPage(root.results[0].page, root.results[0].key)
                onTextChanged: if (text !== "") root.pageShown = false
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: searchInput.text === ""
                    text: "Search settings"
                    color: Colors.surfaceVariantOn
                    font: searchInput.font
                }
            }
            IconButton {
                id: clearSearch
                anchors.right: parent.right
                anchors.rightMargin: Spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                visible: root.searching
                width: visible ? implicitWidth : 0
                iconName: "close"
                onClicked: searchInput.text = ""
            }
        }

        // A few pages and results: plain Repeaters in a Flickable, every item made (no ListView recycling).
        Flickable {
            id: sideFlick
            anchors.top: searchPill.bottom
            anchors.topMargin: Spacing.lg
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Spacing.lg
            anchors.rightMargin: Spacing.lg
            clip: true
            contentHeight: (root.searching ? resultList : pageList).implicitHeight + Spacing.lg
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: pageList
                objectName: "settingsPages"
                width: sideFlick.width
                spacing: ControlSpec.listSpec.segmentedGap
                visible: !root.searching
                Repeater {
                    model: Pages.pages
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        objectName: "settingsPage_" + modelData.id
                        width: pageList.width
                        position: root.segment(index, Pages.pages.length)
                        iconName: modelData.icon
                        avatarTone: modelData.tone
                        text: modelData.title
                        supportingText: modelData.summary
                        selected: !root.narrow && root.currentPage === modelData.id
                        tone: Colors.surfaceContainer
                        onClicked: root.openPage(modelData.id)
                    }
                }
            }

            Column {
                id: resultList
                objectName: "settingsResults"
                width: sideFlick.width
                spacing: ControlSpec.listSpec.segmentedGap
                visible: root.searching
                Repeater {
                    model: root.results
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        objectName: "settingsResult_" + index
                        width: resultList.width
                        position: root.segment(index, root.results.length)
                        iconName: Pages.page(modelData.page).icon
                        text: modelData.title
                        supportingText: modelData.detail
                        tone: Colors.surfaceContainer
                        onClicked: root.openPage(modelData.page, modelData.key)
                    }
                }
                Text {
                    objectName: "settingsNoResults"
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: Spacing.xl
                    visible: root.searching && root.results.length === 0
                    text: "No settings match “" + root.query.trim() + "”"
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.bodyMedium)
                }
            }
        }
    }

    // ---- the page ----
    Rectangle {
        id: pageArea
        visible: !root.narrow || root.pageShown
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.left: root.narrow ? parent.left : sidebar.right
        color: Colors.surface
        radius: root.narrow ? 0 : Shapes.extraLarge
        // square on the window's edges, round toward the sidebar
        topRightRadius: 0
        bottomRightRadius: 0

        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Spacing.xl
            spacing: Spacing.sm
            height: 48
            IconButton {
                objectName: "settingsBack"
                anchors.verticalCenter: parent.verticalCenter
                visible: root.narrow
                iconName: "arrow_back"
                onClicked: root.pageShown = false
            }
            Text {
                objectName: "settingsTitle"
                anchors.verticalCenter: parent.verticalCenter
                text: root.page?.title ?? ""
                color: Colors.surfaceOn
                font: Type.font(Type.headlineSmall)
            }
        }

        Flickable {
            id: pageFlick
            objectName: "settingsPageFlick"
            anchors.top: header.bottom
            anchors.topMargin: Spacing.lg
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Spacing.xl
            anchors.rightMargin: Spacing.xl
            contentHeight: pageColumn.implicitHeight + Spacing.xl
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: pageColumn
                width: pageFlick.width
                spacing: Spacing.xl

                Repeater {
                    model: root.sections
                    delegate: Column {
                        id: section
                        required property var modelData
                        width: pageColumn.width
                        spacing: ControlSpec.listSpec.segmentedGap
                        Text {
                            visible: section.modelData.title !== ""
                            height: implicitHeight + Spacing.sm
                            leftPadding: Spacing.lg
                            text: section.modelData.title
                            color: Colors.primary
                            font: Type.font(Type.titleSmall)
                        }
                        Repeater {
                            model: section.modelData.rows
                            delegate: SettingRow {
                                id: settingRow
                                required property var modelData
                                required property int index
                                width: section.width
                                row: modelData
                                store: root.store
                                position: root.segment(index, section.modelData.rows.length)
                                highlighted: root.highlightKey === modelData.key
                                menuOpen: root.menuKey === modelData.key
                                onToggleMenu: root.toggleMenu(settingRow)
                                onPickPath: root.pathRequested(modelData.key, modelData.filters)
                                onRunAction: root.actionRequested(modelData.key)
                                conditions: root.conditions
                            }
                        }
                    }
                }

                // A page of its own (plan 5.2): its view, loaded only while the page is open (D31). It gets the
                // app (for segment()), the store, and the page's backend.
                Loader {
                    id: pageView
                    objectName: "settingsPageView"
                    active: !!root.page?.view
                    visible: active
                    width: pageColumn.width
                    source: active ? Qt.resolvedUrl(root.page.view) : ""
                }
                Binding { target: pageView.item; property: "app"; value: root; when: pageView.status === Loader.Ready }
                Binding { target: pageView.item; property: "store"; value: root.store; when: pageView.status === Loader.Ready }
                Binding { target: pageView.item; property: "backend"; value: root.backend; when: pageView.status === Loader.Ready }
            }

            // The ring around a setting opened from a search: M3's focus indicator (its color, 3 thick, the
            // list's corner), there at once, then fading out with the highlight. It follows the row while the
            // page is laid out again (niri resizes a new window right after it opens).
            Rectangle {
                id: ring
                objectName: "settingRing"
                property Item target: null
                function show(row) {
                    fading.enabled = false;
                    target = row;
                    place();
                    opacity = 1;
                }
                function place() {
                    if (!target) return;
                    const at = target.mapToItem(pageColumn, 0, 0);
                    x = at.x;
                    y = at.y;
                    width = target.width;
                    height = target.height;
                }
                Connections {
                    target: ring.target
                    function onWidthChanged() { ring.place(); }
                    function onHeightChanged() { ring.place(); }
                }
                Connections {
                    target: pageColumn
                    function onWidthChanged() { Qt.callLater(ring.place); }
                    function onImplicitHeightChanged() { Qt.callLater(ring.place); }
                }
                function fade() {
                    fading.enabled = true;
                    opacity = 0;
                }
                visible: target !== null && opacity > 0
                opacity: 0
                z: 1
                color: "transparent"
                radius: ControlSpec.listSpec.containerShape
                border.width: 3
                border.color: Colors[ControlSpec.listSpec.focusIndicatorColor]
                Behavior on opacity {
                    id: fading
                    EffectsNumber { duration: Motion.duration(Motion.long4) }
                }
            }
        }
    }

    // ---- the open setting's choices: a dialog over a scrim, as Googlebook's (the reference's "Choose modifier
    // key"): pick one, then Done; Cancel, Escape or a press on the scrim leaves the setting as it was ----
    property int pick: -1                           // the choice picked in the dialog, not yet applied
    readonly property var menuChoices: menuRow?.row.choices ?? []
    onMenuKeyChanged: if (menuKey !== "") pick = menuChoices.indexOf(menuRow.current)
    Rectangle {
        objectName: "settingMenuCatcher"
        anchors.fill: parent
        z: 10
        visible: root.menuKey !== "" || opacity > 0     // there from the first frame, while it fades in
        opacity: root.menuKey !== "" ? 1 : 0
        color: Qt.alpha(Colors.scrim, 0.32)
        Behavior on opacity { EffectsNumber { speed: "fast" } }
        MouseArea {
            anchors.fill: parent
            enabled: root.menuKey !== ""
            onPressed: root.menuKey = ""
        }
    }
    PopupLoader {
        id: menu
        objectName: "settingMenu"
        z: 11
        open: root.menuKey !== ""
        origin: Item.Center
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        sourceComponent: Dialog {
            id: choiceDialog
            readonly property var row: root.menuRow
            headline: row?.row.title ?? row?.text ?? ""
            supportingText: row?.row.description ?? ""
            actions: [{ id: "cancel", text: "Cancel", type: "outlined" }, { id: "done", text: "Done", type: "filled" }]
            acceptId: "done"
            dismissId: "cancel"
            onChosen: id => {
                // Done with the current one picked changes nothing
                if (id === "done" && root.pick >= 0 && root.pick !== root.menuChoices.indexOf(row?.current)) root.choose(root.pick);
                else root.menuKey = "";
            }
            Keys.onUpPressed: root.pick = Math.max(0, root.pick - 1)
            Keys.onDownPressed: root.pick = Math.min(root.menuChoices.length - 1, root.pick + 1)
            Component.onCompleted: forceActiveFocus()

            Flickable {
                width: parent.width
                height: Math.min(choiceList.implicitHeight, 6 * ControlSpec.listSpec.itemOneLineContainerHeight)
                contentHeight: choiceList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: choiceList
                    width: parent.width
                    spacing: ControlSpec.listSpec.segmentedGap
                    Repeater {
                        model: root.menuChoices
                        delegate: ListItem {
                            required property var modelData
                            required property int index
                            objectName: "settingChoice_" + index
                            width: choiceList.width
                            position: root.segment(index, root.menuChoices.length)
                            tone: Colors[ControlSpec.dialogSpec.containerColor]
                            selected: root.pick === index
                            iconName: root.pick === index ? "check" : ""
                            text: Model.valueText(choiceDialog.row?.row.key ?? "", modelData, Pages.hints)
                            onClicked: root.pick = index
                        }
                    }
                }
            }
        }
    }
}
