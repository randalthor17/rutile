// The frame of our own app windows (plan 3.1, D88): a TitleBar over the app, and edges to resize the window by,
// since neither niri nor Qt (shell.qml turns its decorations off) draws any. `window` is the FloatingWindow; the
// frame calls its startSystemMove and startSystemResize (the compositor moves and resizes, as with any title
// bar) and flips its `maximized`. Plain QtQuick, so it tests offscreen against a stand-in window.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common

Item {
    id: root

    property var window: null
    property string title: window?.title ?? ""
    property string iconName: ""
    property color color: Colors.surfaceContainerLow
    readonly property bool maximized: window?.maximized ?? false
    readonly property int edge: Spacing.sm     // how far in from the window's side a press resizes
    readonly property alias titleBar: titleBar
    default property alias content: body.data

    signal closeRequested()             // the window decides what closing means (it unloads, D31)

    function toggleMaximized() {
        if (window)
            window.maximized = !window.maximized;
    }
    function resize(edges) {
        if (window && !maximized)
            window.startSystemResize(edges);
    }

    Rectangle {
        anchors.fill: parent
        color: root.color
    }

    TitleBar {
        id: titleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        title: root.title
        iconName: root.iconName
        maximized: root.maximized
        onMoveRequested: if (root.window) root.window.startSystemMove()
        onMaximizeRequested: root.toggleMaximized()
        onCloseRequested: root.closeRequested()
    }

    Item {
        id: body
        anchors.top: titleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }

    // the resize edges: sides, then corners (later, so over them); none while maximized
    Repeater {
        model: [
            { edges: Qt.TopEdge, cursor: Qt.SizeVerCursor },
            { edges: Qt.BottomEdge, cursor: Qt.SizeVerCursor },
            { edges: Qt.LeftEdge, cursor: Qt.SizeHorCursor },
            { edges: Qt.RightEdge, cursor: Qt.SizeHorCursor },
            { edges: Qt.TopEdge | Qt.LeftEdge, cursor: Qt.SizeFDiagCursor },
            { edges: Qt.BottomEdge | Qt.RightEdge, cursor: Qt.SizeFDiagCursor },
            { edges: Qt.TopEdge | Qt.RightEdge, cursor: Qt.SizeBDiagCursor },
            { edges: Qt.BottomEdge | Qt.LeftEdge, cursor: Qt.SizeBDiagCursor }
        ]
        delegate: MouseArea {
            required property var modelData
            readonly property bool atTop: modelData.edges & Qt.TopEdge
            readonly property bool atBottom: modelData.edges & Qt.BottomEdge
            readonly property bool atLeft: modelData.edges & Qt.LeftEdge
            readonly property bool atRight: modelData.edges & Qt.RightEdge
            readonly property bool corner: (atTop || atBottom) && (atLeft || atRight)
            objectName: "resizeEdge_" + modelData.edges
            visible: !root.maximized
            x: atRight ? root.width - width : 0
            y: atBottom ? root.height - height : 0
            width: atLeft || atRight ? (corner ? 2 * root.edge : root.edge) : root.width
            height: atTop || atBottom ? (corner ? 2 * root.edge : root.edge) : root.height
            cursorShape: modelData.cursor
            onPressed: root.resize(modelData.edges)
        }
    }
}
