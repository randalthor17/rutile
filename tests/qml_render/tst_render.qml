import QtQuick
import QtTest
import qs.common
import qs.gallery

// Not part of `make check`: tools/qtws.py render runs only this file and saves the PNG.
TestCase {
    id: root
    name: "Render"
    width: 1180
    height: 900
    visible: true
    when: windowShown

    property var cfg: readJson("../data/render.json")
    property var paths: readJson("../data/fontpaths.json")

    function readJson(rel) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }

    Component { id: loaderComp; FontLoader {} }
    Component { id: galleryComp; GalleryContent { width: 1180; height: 900 } }

    function test_render_gallery() {
        for (var k in paths) {
            var l = loaderComp.createObject(root, { source: "file://" + encodeURI(paths[k]) });
            tryCompare(l, "status", FontLoader.Ready, 10000);
        }
        Colors.mode = cfg.mode;
        var g = createTemporaryObject(galleryComp, root, { width: cfg.width });
        wait(600);
        var flick = g.flickable;
        var step = flick.height - 40;
        var total = flick.contentHeight;
        var n = Math.ceil((total - flick.height) / step) + 1;
        for (var i = 0; i < n; i++) {
            flick.contentY = Math.min(i * step, total - flick.height);
            wait(120);
            var img = grabImage(g);
            var path = cfg.out.replace(".png", "-" + (i + 1) + ".png");
            img.save(path);   // returns undefined in Qt Quick Test; the caller checks the files exist
        }
        console.log("slices: " + n + ", content height " + total);
    }
}
