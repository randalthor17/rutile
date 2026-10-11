// Component gallery window. Run from the repo root with:   quickshell -p shell/gallery.qml
// (the shell root is this file's directory, so `import qs.common` resolves to shell/common).
import QtQuick
import Quickshell
import qs.common
import qs.gallery

ShellRoot {
    PaletteWatcher {}

    FloatingWindow {
        title: "Rutile gallery"
        implicitWidth: 1180
        implicitHeight: 860
        color: Colors.surface

        GalleryContent {
            anchors.fill: parent
        }
    }
}
