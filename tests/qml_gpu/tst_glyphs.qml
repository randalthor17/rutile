import QtQuick
import QtTest
import qs.common
import qs.components

// Runs through the REAL scene graph (OpenGL/Vulkan/Metal), not the software renderer: filled
// Material Symbols glyphs used to render with holes there. `make check-gpu` runs this in a session.
TestCase {
    id: root
    name: "GpuGlyphs"
    width: 400
    height: 300
    visible: true
    when: windowShown

    property var paths: readJson("../data/fontpaths.json")

    function readJson(rel) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }

    Component { id: loaderComp; FontLoader {} }
    Component { id: iconComp; Icon {} }
    Component { id: buttonComp; Button {} }

    Component { id: probeComp; Text {} }

    // FILL only exists as an axis where Qt has font.variableAxes; elsewhere there is nothing filled to check.
    function requireAxes() {
        var probe = createTemporaryObject(probeComp, root, {});
        var supported = probe.font.variableAxes !== undefined;
        probe.destroy();
        if (!supported)
            skip("this Qt has no font.variableAxes, so filled glyphs cannot be requested");
    }

    function loadIcons() {
        verify(paths.icons !== undefined, "icon font path missing");
        var l = loaderComp.createObject(root, { source: "file://" + encodeURI(paths.icons) });
        tryCompare(l, "status", FontLoader.Ready, 10000);
    }

    // Light pixels (on a black glyph over white) inside a disc around the glyph's center.
    function holes(item, radius) {
        wait(120);
        var img = grabImage(item), cx = Math.round(img.width / 2), cy = Math.round(img.height / 2), n = 0;
        for (var y = cy - radius; y <= cy + radius; y++)
            for (var x = cx - radius; x <= cx + radius; x++) {
                if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > radius * radius) continue;
                if ((img.red(x, y) + img.green(x, y) + img.blue(x, y)) / 3 > 96) n++;
            }
        return n;
    }

    function test_filled_glyphs_are_solid_in_the_middle_at_several_sizes() {
        requireAxes();
        loadIcons();
        var cases = [["favorite", 16], ["favorite", 24], ["favorite", 48], ["favorite", 96],
                     ["star", 24], ["star", 48], ["star", 96]];
        for (var i = 0; i < cases.length; i++) {
            var icon = createTemporaryObject(iconComp, root, { name: cases[i][0], size: cases[i][1], fill: 1, color: "black" });
            var radius = Math.max(2, Math.round(cases[i][1] * 0.14));
            compare(holes(icon, radius), 0, cases[i][0] + " " + cases[i][1] + "px has light holes inside the filled glyph");
            icon.destroy();
        }
    }

    function test_selected_toggle_button_icon_is_solid() {
        requireAxes();
        loadIcons();
        var b = createTemporaryObject(buttonComp, root, { text: "Toggle", iconName: "favorite", type: "filled", size: "m",
                                                          toggle: true, checked: true, x: 20, y: 20 });
        wait(400);
        var img = grabImage(b), fill = Colors.primary, light = 0, total = 0;
        // the icon sits left of the label: sample a small disc at its center
        var cx = b.spec.leading + b.spec.icon / 2, cy = b.height / 2, r = 4;
        for (var y = Math.round(cy - r); y <= Math.round(cy + r); y++)
            for (var x = Math.round(cx - r); x <= Math.round(cx + r); x++) {
                // a disc, not the square: the square's corners reach the heart's slanted lower edges, and a
                // 1 px shift in glyph placement (seen on Qt 6.12) put one corner pixel outside the glyph
                if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > r * r) continue;
                total++;
                // the glyph is drawn in primaryOn (dark on this container); holes would show the container color
                if (Math.abs(img.red(x, y) / 255 - fill.r) < 0.06 && Math.abs(img.green(x, y) / 255 - fill.g) < 0.06) light++;
            }
        compare(light, 0, light + " of " + total + " pixels at the heart's center show the container color through the glyph");
    }
}
