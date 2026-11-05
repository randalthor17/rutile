pragma ComponentBehavior: Bound
// The clipboard history picker (D119): a search field over what was copied, newest first, as a list. The keyboard
// stays in the field: Up and Down move, Enter copies the current one back (then paste it with Ctrl+V) and closes,
// Delete forgets it (also its row's button), Escape closes; "Clear all" forgets everything. Plain QtQuick on
// `entries` (Clipboard.parse's), so it tests offscreen; ClipboardWindow.qml gives it ClipboardService's. It grows
// in and out with the shared popup motion (D43), then reports `hidden`.
import QtQuick
import qs.common
import qs.components
import "Clipboard.js" as Clipboard

Rectangle {
    id: root

    property var entries: []
    property bool reading: false
    property alias query: field.text
    property bool shown: true
    readonly property var results: Clipboard.filter(entries, query)
    readonly property alias listView: list

    signal chosen(var entry)
    signal removed(var entry)
    signal wipeRequested()
    signal closeRequested()
    signal hidden()

    function chooseCurrent() {
        const e = results[list.currentIndex];
        if (e) root.chosen(e);
    }
    function removeCurrent() {
        const e = results[list.currentIndex];
        if (e) root.removed(e);
    }
    onResultsChanged: list.currentIndex = results.length > 0 ? Math.min(Math.max(0, list.currentIndex), results.length - 1) : -1

    implicitWidth: 480
    implicitHeight: content.height + 2 * Spacing.lg
    width: implicitWidth
    height: implicitHeight
    radius: Shapes.extraLarge
    color: Panels.tint(Colors.surfaceContainer)

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
                name: "content_paste_search"
                size: Spacing.xl
                color: Colors.surfaceVariantOn
            }
            Text {
                anchors.left: field.left
                anchors.verticalCenter: parent.verticalCenter
                visible: field.text === ""
                text: "Search the clipboard"
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodyLarge)
            }
            TextInput {
                id: field
                objectName: "clipboardSearch"
                anchors.left: searchIcon.right
                anchors.leftMargin: Spacing.md
                anchors.right: parent.right
                anchors.rightMargin: Spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                color: Colors.surfaceOn
                selectionColor: Colors.primary
                selectedTextColor: Colors.primaryOn
                font: Type.font(Type.bodyLarge)
                Keys.onUpPressed: list.decrementCurrentIndex()
                Keys.onDownPressed: list.incrementCurrentIndex()
                Keys.onReturnPressed: root.chooseCurrent()
                Keys.onEnterPressed: root.chooseCurrent()
                Keys.onDeletePressed: event => {
                    // in an empty field Delete forgets the current entry; with text it deletes text as usual
                    if (field.text === "") root.removeCurrent();
                    else event.accepted = false;
                }
                Keys.onEscapePressed: root.closeRequested()
            }
        }

        Text {
            objectName: "clipboardEmpty"
            visible: !root.reading && root.results.length === 0
            width: parent.width
            topPadding: Spacing.lg
            bottomPadding: Spacing.lg
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.entries.length === 0 ? "Nothing copied yet" : "Nothing matches"
            color: Colors.surfaceVariantOn
            font: Type.font(Type.bodyMedium)
        }

        ListView {
            id: list
            objectName: "clipboardList"
            visible: root.results.length > 0
            width: parent.width
            height: Math.min(contentHeight, 6 * ControlSpec.listSpec.itemOneLineContainerHeight + 5 * spacing)
            clip: true
            spacing: ControlSpec.listSpec.segmentedGap
            model: root.results
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            delegate: ListItem {
                id: row
                required property var modelData
                required property int index
                objectName: "clipboardEntry_" + index
                width: list.width
                position: root.results.length === 1 ? "single" : index === 0 ? "first"
                        : index === root.results.length - 1 ? "last" : "middle"
                iconName: modelData.image ? "image" : "content_paste"
                text: modelData.text.replace(/\s+/g, " ").trim()
                selected: index === list.currentIndex
                onClicked: root.chosen(modelData)
                IconButton {
                    objectName: "clipboardDelete_" + row.index
                    iconName: "close"
                    size: "xs"
                    onClicked: root.removed(row.modelData)
                }
            }
        }

        Item {
            visible: root.entries.length > 0
            width: parent.width
            height: clear.height
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Enter copies; paste with Ctrl+V"
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodySmall)
            }
            Button {
                id: clear
                objectName: "clipboardClear"
                anchors.right: parent.right
                type: "text"
                text: "Clear all"
                onClicked: root.wipeRequested()
            }
        }
    }
}
