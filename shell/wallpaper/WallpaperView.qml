// The wallpaper (plan 2.9): `path` fills the view, cropped to cover it, decoded at the view's size (D31). A new path
// loads in the second image, above the one showing, and fades in once it has loaded; then the old one is dropped
// and the two trade places, so two images are decoded only during the fade. A path that does not load leaves the
// current one. With none, the surface color shows.
import QtQuick
import qs.common

Rectangle {
    id: root

    property string path: ""
    // The image showing and the one loading or fading in (exposed for tests).
    property Image front: a
    property Image back: b
    readonly property bool fading: fade.running

    color: Colors.surface

    function url(p) { return p ? "file://" + p : ""; }

    onPathChanged: {
        fade.stop();
        back.opacity = 0;
        if (url(path) === front.source.toString()) {      // back to the one showing: drop what was loading
            back.source = "";
            return;
        }
        back.source = url(path);
        if (path === "") front.source = "";                // no wallpaper: the surface color
    }

    function loaded(img) {
        if (img !== back || img.source.toString() === "") return;
        if (img.status !== Image.Ready) {
            if (img.status === Image.Error) img.source = "";
            return;
        }
        fade.restart();                                   // with motion off it finishes at once
    }
    // The faded-in one becomes the front; the old one is dropped and goes behind.
    function swap() {
        const old = front;
        front = back;
        back = old;
        old.source = "";
        old.opacity = 0;
    }

    Image {
        id: a
        objectName: "wallpaperA"
        anchors.fill: parent
        z: root.front === a ? 0 : 1
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        onStatusChanged: root.loaded(a)
    }
    Image {
        id: b
        objectName: "wallpaperB"
        anchors.fill: parent
        z: root.front === b ? 0 : 1
        opacity: 0
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        onStatusChanged: root.loaded(b)
    }

    NumberAnimation {      // motion-speed: Motion.duration
        id: fade
        target: root.back
        property: "opacity"
        to: 1
        duration: Motion.duration(Motion.long2)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.easing.standard
        onFinished: root.swap()
    }
}
