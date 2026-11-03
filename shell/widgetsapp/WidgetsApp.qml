// The Widgets app's contents (plan 4.5, D82), as Googlebook's Custom widgets: the categories on the left, and the
// chosen one's widgets on the right as cards drawn live (WidgetCard). A category lists the templates that come
// with the shell (widgets/templates); "Your widgets" lists the user's own folder. Widgets are JSON files written by
// hand (widgets/spec.schema.json): using a template copies it there to be changed. Plain QtQuick: the window reads
// the files and hands over `templates`, `mine` and `specs`, and does what the signals ask.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import "Gallery.js" as Gallery

Rectangle {
    id: root

    property string currentCategory: Gallery.categories[0].id
    property var templates: []              // [{path, name}], every template (a scan)
    property var mine: []                   // [{path, name}], the user's widgets
    property var specs: ({})                // path: spec, for what is shown
    property var allow: []                  // widgets.httpAllow
    property string userDir: ""
    readonly property bool showingMine: currentCategory === "yours"
    readonly property var shown: showingMine ? mine : Gallery.templatesIn(templates, currentCategory)
    readonly property var category: Gallery.category(currentCategory)

    signal useRequested(string path)        // a template
    signal editRequested(string path)       // one of the user's
    signal placeRequested(string path)
    signal folderRequested()

    // Opens a category; false for an unknown one.
    function openCategory(id) {
        if (!Gallery.category(id))
            return false;
        currentCategory = id;
        cardsFlick.contentY = 0;
        return true;
    }
    function segment(i, n) {
        return n === 1 ? "single" : i === 0 ? "first" : i === n - 1 ? "last" : "middle";
    }

    color: Colors.surfaceContainerLow

    Flickable {
        id: sideFlick
        width: 320
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Spacing.lg
        clip: true
        contentHeight: categoryList.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: categoryList
            width: sideFlick.width
            spacing: ControlSpec.listSpec.segmentedGap
            Repeater {
                model: Gallery.categories
                delegate: ListItem {
                    required property var modelData
                    required property int index
                    objectName: "galleryCategory_" + modelData.id
                    width: categoryList.width
                    position: root.segment(index, Gallery.categories.length)
                    iconName: modelData.icon
                    avatarTone: modelData.tone
                    text: modelData.title
                    supportingText: modelData.summary
                    selected: root.currentCategory === modelData.id
                    tone: Colors.surfaceContainer
                    onClicked: root.openCategory(modelData.id)
                }
            }
        }
    }

    Flickable {
        id: cardsFlick
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: sideFlick.right
        anchors.right: parent.right
        anchors.leftMargin: Spacing.xl
        anchors.rightMargin: Spacing.lg
        clip: true
        contentHeight: page.implicitHeight + 2 * Spacing.lg
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: page
            y: Spacing.lg
            width: cardsFlick.width
            spacing: Spacing.lg

            Text {
                text: root.category?.title ?? ""
                color: Colors.surfaceOn
                font: Type.font(Type.headlineSmall)
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.showingMine
                      ? "Widgets are JSON files in " + root.userDir + ". Edit one and the desktop shows it when you save."
                      : "Use a template to copy it to your widgets, put it on the desktop and open it to change."
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodyMedium)
            }
            Button {
                objectName: "galleryFolder"
                visible: root.showingMine
                type: "outlined"
                iconName: "folder_open"
                text: "Open the folder"
                onClicked: root.folderRequested()
            }
            Text {
                objectName: "galleryEmpty"
                visible: root.shown.length === 0
                width: parent.width
                wrapMode: Text.Wrap
                text: root.showingMine ? "No widgets yet: use a template, or write one (widgets/README.md)."
                                       : "No templates found."
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodyLarge)
            }
            Flow {
                id: cards
                width: parent.width
                spacing: Spacing.lg
                // as many columns of at least 320 as fit, sharing the width
                readonly property int across: Math.max(1, Math.floor((width + spacing) / (320 + spacing)))
                readonly property real cardWidth: Math.floor((width - (across - 1) * spacing) / across)
                Repeater {
                    model: root.shown
                    delegate: WidgetCard {
                        required property var modelData
                        objectName: "galleryCard_" + Gallery.baseName(modelData.path)
                        width: cards.cardWidth
                        entry: modelData
                        spec: root.specs[modelData.path] ?? null
                        mine: root.showingMine
                        allow: root.allow
                        onUsed: root.useRequested(modelData.path)
                        onEdited: root.editRequested(modelData.path)
                        onPlaced: root.placeRequested(modelData.path)
                    }
                }
            }
        }
    }
}
