// A window that shows one widget file with its live data (plan 4.6's preview, D80), until the desktop grid (4.4)
// shows widgets: `rutile-shell widgets preview FILE`. The file is read again whenever it is saved, so a widget
// can be written and watched at once; below the widget, what the renderer left out and what its sources said.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "WidgetSpec.js" as Spec

FloatingWindow {
    id: root

    property string path: ""
    property var spec: null
    property string readError: ""
    readonly property var problems: readError !== "" ? [readError] : host.problems
    readonly property var sourceErrors: Object.keys(sources.errors).map(n => n + ": " + sources.errors[n])
    readonly property alias values: sources.values

    signal finished()

    function parse() {
        if (!file.loaded) {
            spec = null;
            readError = "cannot read " + path;
            return;
        }
        try {
            spec = JSON.parse(file.text());
            readError = "";
        } catch (e) {
            spec = null;
            readError = "not JSON: " + e.message;
        }
    }

    title: "Widget preview: " + (spec?.name ?? path.substring(path.lastIndexOf("/") + 1))
    implicitWidth: 360 + 2 * Spacing.xl
    implicitHeight: Math.max(240, content.implicitHeight + 2 * Spacing.xl)
    color: Colors.surface
    onClosed: root.finished()

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse()
        onLoadFailed: root.parse()
    }
    WidgetSources {
        id: sources
        spec: root.spec
    }

    Flickable {
        anchors.fill: parent
        contentHeight: content.implicitHeight + 2 * Spacing.xl
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: content
            x: Spacing.xl
            y: Spacing.xl
            width: parent.width - 2 * Spacing.xl
            spacing: Spacing.lg
            WidgetHost {
                id: host
                objectName: "previewWidget"
                width: parent.width
                spec: root.spec
                values: sources.values
            }
            Repeater {
                model: root.problems.concat(root.sourceErrors)
                delegate: Text {
                    required property string modelData
                    width: content.width
                    wrapMode: Text.Wrap
                    text: modelData
                    color: Colors.error
                    font: Type.font(Type.bodySmall)
                }
            }
        }
    }
}
