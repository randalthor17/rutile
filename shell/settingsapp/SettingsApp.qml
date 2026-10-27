// The settings app's contents (plan 5.1), as Googlebook's Settings: a sidebar with a search field and the pages
// (Pages.js) as a list with tonal icon circles, and the chosen page on the right: its title and its settings in
// segmented groups (SettingRow), an Advanced group last. Typing in the search field lists matching pages and
// settings instead (Model.search); choosing one opens its page and marks the setting for a moment. Narrower than
// `narrowWidth`, only one side shows: the list, or the page with a back button.
// `store` is the Settings service, or anything with value(key), set(key, value), isManaged(key) and configDir (the
// tests' fake). A path setting asks for a file (`pathRequested`); the window has the file chooser. Plain QtQuick,
// so it tests offscreen; SettingsWindow puts it in a window.
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

    signal pathRequested(string key, var filters)

    // Opens a page (and marks one of its settings); false for an unknown page.
    function openPage(id, key) {
        if (!Pages.page(id)) return false;
        menuKey = "";
        currentPage = id;
        highlightKey = key ?? "";
        searchInput.text = "";
        pageShown = true;
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
    // Opens a row's choices under it (above it when there is no room below), or closes them.
    function toggleMenu(row) {
        if (menuKey === row.row.key) {
            menuKey = "";
            return;
        }
        menuRow = row;
        const at = row.mapToItem(root, 0, 0);
        menu.below = at.y + row.height + menu.wanted <= root.height - Spacing.sm;
        menu.at = at;
        menuKey = row.row.key;
    }
    function choose(index) {
        const r = menuRow;
        menuKey = "";
        if (r) store.set(r.row.key, r.row.choices[index]);
    }
    function segment(i, n) {
        return n === 1 ? "single" : i === 0 ? "first" : i === n - 1 ? "last" : "middle";
    }

    color: Colors.surfaceContainerLow

    Timer {
        id: unmark
        interval: 2000
        onTriggered: root.highlightKey = ""
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
                            }
                        }
                    }
                }

                // About: where the settings live (D45).
                Loader {
                    active: root.currentPage === "about"
                    visible: active
                    width: pageColumn.width
                    sourceComponent: Column {
                        spacing: ControlSpec.listSpec.segmentedGap
                        ListItem {
                            objectName: "aboutSettingsFile"
                            width: parent.width
                            position: "first"
                            iconName: "description"
                            text: "Your settings"
                            supportingText: root.store.configDir + "/settings.json"
                        }
                        ListItem {
                            width: parent.width
                            position: "middle"
                            iconName: "lock"
                            text: "Set in Nix (home-manager)"
                            supportingText: root.store.configDir + "/managed.json"
                        }
                        ListItem {
                            width: parent.width
                            position: "last"
                            iconName: "terminal"
                            text: "From a script or keybind"
                            supportingText: "quickshell ipc call settings open <page>"
                        }
                    }
                }
            }
        }
    }

    // ---- the open setting's choices, above everything; a press anywhere else closes them ----
    MouseArea {
        objectName: "settingMenuCatcher"
        anchors.fill: parent
        z: 10
        visible: root.menuKey !== ""
        onPressed: root.menuKey = ""
    }
    PopupLoader {
        id: menu
        objectName: "settingMenu"
        property point at: Qt.point(0, 0)              // the row's top left, when it opened
        property bool below: true
        readonly property real wanted: (root.menuRow?.row.choices.length ?? 0) * ControlSpec.listSpec.itemOneLineContainerHeight + Spacing.lg
        z: 11
        open: root.menuKey !== ""
        origin: below ? Item.TopRight : Item.BottomRight
        x: Math.max(Spacing.sm, at.x + (root.menuRow?.width ?? 0) - width - Spacing.sm)
        y: below ? at.y + (root.menuRow?.height ?? 0) : Math.max(Spacing.sm, at.y - height)
        sourceComponent: Menu {
            readonly property var row: root.menuRow
            items: (row?.row.choices ?? []).map((v, i) => ({ id: String(i), text: Model.valueText(row.row.key, v, Pages.hints),
                                                             icon: v === row.current ? "check" : "" }))
            itemPrefix: "settingChoice_"
            onChosen: id => root.choose(Number(id))
        }
    }
}
