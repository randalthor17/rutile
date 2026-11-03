// The files source (plan 4.2, D79): a text file, read again when it changes (`~/` is the home folder).
import QtQuick
import qs.widgethost
import Quickshell
import Quickshell.Io
import "../Sources.js" as Sources

WidgetSource {
    id: root
    readonly property string path: {
        const p = options.path ?? "";
        return p.startsWith("~/") ? Quickshell.env("HOME") + p.substring(1) : p;
    }
    value: Sources.files(file.loaded ? file.text() : "")
    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
    }
}
