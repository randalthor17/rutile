pragma ComponentBehavior: Bound
// The Wallhaven browser (D128), after Noctalia's wallhaven plugin: a search field, the sort and shape menus, filter
// chips (categories, purity; NSFW only with an API key; "At least my screen"), the results as a grid of thumbnails,
// and pages. A click on a thumbnail asks to set it as the wallpaper (`chosen`); it shows "Downloading" until done.
// Plain QtQuick on WallhavenService's members, so it tests offscreen; WallhavenWindow.qml gives it the service's.
// Thumbnails load straight from Wallhaven at their small size and go with the panel (D31). It grows in and out
// with the shared popup motion (D43), then reports `hidden`.
import QtQuick
import QtQuick.Effects
import qs.common
import qs.components
import "Wallhaven.js" as Wallhaven

Rectangle {
    id: root

    property var wallpapers: []
    property var filters: Wallhaven.defaults()
    property int page: 1
    property int pages: 1
    property bool loading: false
    property string error: ""
    property string applying: ""
    property bool hasKey: false
    property string screenSize: ""          // "WxH" in pixels, for "At least my screen"
    property bool shown: true
    property string menuOpen: ""            // "sort", "ratio" or ""
    readonly property alias grid: grid

    signal searchRequested(int page)
    signal filtersEdited(var changes)
    signal chosen(var wallpaper)
    signal closeRequested()
    signal hidden()

    function label(list, id) {
        return (list.find(x => x.id === id) ?? list[0]).text;
    }

    implicitWidth: 880
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

        Row {
            width: parent.width
            spacing: Spacing.sm

            Rectangle {
                width: parent.width - sortChip.width - ratioChip.width - close.width - 3 * parent.spacing
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
                    text: "Search Wallhaven (nature, city night…)"
                    color: Colors.surfaceVariantOn
                    font: Type.font(Type.bodyLarge)
                }
                TextInput {
                    id: field
                    objectName: "wallhavenSearch"
                    anchors.left: searchIcon.right
                    anchors.leftMargin: Spacing.md
                    anchors.right: parent.right
                    anchors.rightMargin: Spacing.lg
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    clip: true
                    text: root.filters.query ?? ""
                    color: Colors.surfaceOn
                    selectionColor: Colors.primary
                    selectedTextColor: Colors.primaryOn
                    font: Type.font(Type.bodyLarge)
                    Keys.onReturnPressed: root.filtersEdited({ query: text })
                    Keys.onEnterPressed: root.filtersEdited({ query: text })
                    Keys.onEscapePressed: {
                        if (root.menuOpen !== "") root.menuOpen = "";
                        else root.closeRequested();
                    }
                }
            }
            Chip {
                id: sortChip
                objectName: "wallhavenSort"
                anchors.verticalCenter: parent.verticalCenter
                iconName: "sort"
                trailingIconName: "arrow_drop_down"
                text: root.label(Wallhaven.SORTS, root.filters.sorting)
                onClicked: root.menuOpen = root.menuOpen === "sort" ? "" : "sort"
            }
            Chip {
                id: ratioChip
                objectName: "wallhavenRatio"
                anchors.verticalCenter: parent.verticalCenter
                iconName: "aspect_ratio"
                trailingIconName: "arrow_drop_down"
                text: root.label(Wallhaven.RATIOS, root.filters.ratio)
                onClicked: root.menuOpen = root.menuOpen === "ratio" ? "" : "ratio"
            }
            IconButton {
                id: close
                objectName: "wallhavenClose"
                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                onClicked: root.closeRequested()
            }
        }

        Flow {
            width: parent.width
            spacing: Spacing.sm
            Repeater {
                model: [{ key: "general", text: "General" }, { key: "anime", text: "Anime" },
                        { key: "people", text: "People" }, { key: "sfw", text: "SFW" },
                        { key: "sketchy", text: "Sketchy" }, { key: "nsfw", text: "NSFW" }]
                delegate: Chip {
                    required property var modelData
                    objectName: "wallhavenFilter_" + modelData.key
                    type: "filter"
                    controlled: true
                    text: modelData.text
                    enabled: modelData.key !== "nsfw" || root.hasKey
                    selected: root.filters[modelData.key] === true && enabled
                    onToggled: wanted => {
                        const c = {};
                        c[modelData.key] = wanted;
                        root.filtersEdited(c);
                    }
                }
            }
            Chip {
                objectName: "wallhavenAtLeast"
                type: "filter"
                controlled: true
                visible: root.screenSize !== ""
                text: "At least my screen"
                selected: root.filters.atLeast !== "" && root.filters.atLeast !== undefined
                onToggled: wanted => root.filtersEdited({ atLeast: wanted ? root.screenSize : "" })
            }
        }

        Item {
            width: parent.width
            height: 3.5 * grid.cellHeight

            GridView {
                id: grid
                objectName: "wallhavenGrid"
                anchors.fill: parent
                visible: root.wallpapers.length > 0
                clip: true
                cellWidth: Math.floor(width / 4)
                cellHeight: Math.round(cellWidth * 2 / 3)
                boundsBehavior: Flickable.StopAtBounds
                model: root.wallpapers
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    objectName: "wallhavenTile_" + index
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: frame
                        anchors.fill: parent
                        anchors.margins: Spacing.xs
                        radius: Shapes.medium
                        color: Colors.surfaceContainerHigh

                        Image {
                            id: thumb
                            anchors.fill: parent
                            visible: false
                            source: tile.modelData.thumb
                            sourceSize.width: width
                            sourceSize.height: height
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            id: mask
                            anchors.fill: parent
                            radius: frame.radius
                            layer.enabled: true
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: parent
                            visible: thumb.status === Image.Ready
                            source: thumb
                            maskEnabled: true
                            maskSource: mask
                        }
                        // sketchy and NSFW ones marked, as Wallhaven marks them
                        Rectangle {
                            anchors.fill: parent
                            radius: frame.radius
                            color: "transparent"
                            visible: tile.modelData.purity !== "sfw" || hover.containsMouse
                            border.width: Spacing.xs / 2
                            border.color: hover.containsMouse ? Colors.primary
                                        : tile.modelData.purity === "nsfw" ? Colors.error : Colors.tertiary
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Spacing.xs
                            width: resolution.implicitWidth + Spacing.sm
                            height: resolution.implicitHeight
                            radius: height / 2
                            color: Colors.scrim
                            opacity: 0.7
                            visible: hover.containsMouse
                        }
                        Text {
                            id: resolution
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Spacing.xs
                            rightPadding: Spacing.xs
                            visible: hover.containsMouse
                            text: tile.modelData.resolution.replace("x", " × ")
                            color: Colors.inverseOnSurface
                            font: Type.font(Type.labelSmall)
                        }
                        Rectangle {
                            objectName: "wallhavenApplying_" + tile.index
                            anchors.fill: parent
                            radius: frame.radius
                            visible: root.applying === tile.modelData.id
                            color: Qt.alpha(Colors.scrim, 0.6)
                            Text {
                                anchors.centerIn: parent
                                text: "Downloading…"
                                color: Colors.inverseOnSurface
                                font: Type.font(Type.labelLarge)
                            }
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.applying === "" ? Qt.PointingHandCursor : Qt.BusyCursor
                            onClicked: if (root.applying === "") root.chosen(tile.modelData)
                        }
                    }
                }
            }

            Text {
                objectName: "wallhavenMessage"
                anchors.centerIn: parent
                width: parent.width
                visible: root.loading || root.error !== "" || root.wallpapers.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.loading ? "Searching…" : root.error !== "" ? root.error : "No wallpapers found"
                color: root.error !== "" && !root.loading ? Colors.error : Colors.surfaceVariantOn
                font: Type.font(Type.bodyLarge)
            }
        }

        Item {
            width: parent.width
            height: previous.height
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Click one to make it your wallpaper"
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodySmall)
            }
            Row {
                anchors.right: parent.right
                spacing: Spacing.sm
                IconButton {
                    id: previous
                    objectName: "wallhavenPrevious"
                    iconName: "chevron_left"
                    enabled: !root.loading && root.page > 1
                    onClicked: root.searchRequested(root.page - 1)
                }
                Text {
                    objectName: "wallhavenPage"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Page " + root.page + " of " + root.pages
                    color: Colors.surfaceOn
                    font: Type.font(Type.labelLarge)
                }
                IconButton {
                    objectName: "wallhavenNext"
                    iconName: "chevron_right"
                    enabled: !root.loading && root.page < root.pages
                    onClicked: root.searchRequested(root.page + 1)
                }
            }
        }
    }

    // the sort and shape menus, under their chips
    PopupLoader {
        open: root.menuOpen === "sort"
        origin: Item.TopLeft
        x: content.x + sortChip.x
        y: content.y + sortChip.y + sortChip.height + Spacing.xs
        z: 1
        sourceComponent: Menu {
            minimumWidth: 160
            itemPrefix: "wallhavenSort_"
            items: Wallhaven.SORTS.map(s => ({ id: s.id, text: s.text, icon: "", check: "radio",
                                               checked: s.id === root.filters.sorting }))
            onChosen: id => {
                root.menuOpen = "";
                root.filtersEdited({ sorting: id });
            }
        }
    }
    PopupLoader {
        open: root.menuOpen === "ratio"
        origin: Item.TopLeft
        x: content.x + ratioChip.x
        y: content.y + ratioChip.y + ratioChip.height + Spacing.xs
        z: 1
        sourceComponent: Menu {
            minimumWidth: 160
            itemPrefix: "wallhavenRatio_"
            items: Wallhaven.RATIOS.map(r => ({ id: r.id || "any", text: r.text, icon: "", check: "radio",
                                                checked: r.id === (root.filters.ratio ?? "") }))
            onChosen: id => {
                root.menuOpen = "";
                root.filtersEdited({ ratio: id === "any" ? "" : id });
            }
        }
    }
}
