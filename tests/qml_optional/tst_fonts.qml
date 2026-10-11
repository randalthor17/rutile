import QtQuick
import QtTest
import qs.common
import qs.components

// Only part of the run when the real font files were found (see tools/qtws.py).
TestCase {
    id: root
    name: "FontFiles"
    width: 600
    height: 400
    visible: true
    when: windowShown     // pixel checks below need a rendered window

    property var paths: readJson("../data/fontpaths.json")

    function readJson(rel) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }

    Component { id: loaderComp; FontLoader {} }
    Component { id: textComp; Text { text: "Hamburgefonstiv 0123456789 Settings"; font.pixelSize: 24 } }

    function load(path) {
        var l = loaderComp.createObject(root, { source: "file://" + encodeURI(path) });
        tryCompare(l, "status", FontLoader.Ready, 10000);
        return l;
    }

    function test_text_font_loads_with_the_configured_family() {
        verify(paths.text !== undefined, "text font path missing");
        var l = load(paths.text);
        compare(l.name, Fonts.textFamily);
        verify(Qt.fontFamilies().indexOf(Fonts.textFamily) >= 0);
    }

    function test_icon_font_loads_with_the_configured_family() {
        if (paths.icons === undefined) skip("icon font not available");
        var l = load(paths.icons);
        compare(l.name, Fonts.iconFamily);
        verify(Qt.fontFamilies().indexOf(Fonts.iconFamily) >= 0);
    }

    function test_type_font_helper_uses_the_loaded_family() {
        load(paths.text);
        var f = Type.font(Type.bodyLarge);
        compare(f.family, Fonts.textFamily);
        compare(f.pixelSize, 16);
    }

    // Axis control needs a Qt with font.variableAxes (recent Qt; Qt 6.4 has none). Detected by
    // feature, not by version: where it is missing the test skips and says why.
    function test_variable_axes_change_glyph_widths_when_qt_supports_them() {
        load(paths.text);
        var probe = textComp.createObject(root, { "font.family": Fonts.textFamily });
        var supported = probe.font.variableAxes !== undefined;
        probe.destroy();
        if (!supported)
            skip("this Qt has no font.variableAxes, so axis control cannot be tested here");
        var light = textComp.createObject(root, { "font.family": Fonts.textFamily, "font.variableAxes": { "wght": 300 } });
        var heavy = textComp.createObject(root, { "font.family": Fonts.textFamily, "font.variableAxes": { "wght": 800 } });
        verify(heavy.implicitWidth > light.implicitWidth,
               "wght 800 width " + heavy.implicitWidth + " should exceed wght 300 width " + light.implicitWidth);
        light.destroy();
        heavy.destroy();
    }

    // Type.font() sets wght/opsz through font.variableAxes where Qt has it. Check the axes are on the
    // font it returns, then that heavier weights come out wider. Emphasized styles also change letter
    // spacing (bodyLarge 0.5 px vs bodyLargeEmphasized 0.15 px), which can outweigh a small weight
    // step, so tracking is zeroed on both sides and only the weight differs.
    function test_emphasized_styles_carry_exact_axes_and_render_heavier() {
        load(paths.text);
        var probe = textComp.createObject(root, { "font.family": Fonts.textFamily });
        var supported = probe.font.variableAxes !== undefined;
        probe.destroy();
        if (!supported)
            skip("this Qt has no font.variableAxes, so exact weights cannot be tested here");
        var pairs = [["bodyLarge", "bodyLargeEmphasized"], ["titleMedium", "titleMediumEmphasized"],
                     ["labelLarge", "labelLargeEmphasized"], ["headlineSmall", "headlineSmallEmphasized"]];
        for (var i = 0; i < pairs.length; i++) {
            var base = Type[pairs[i][0]], emph = Type[pairs[i][1]];
            verify(emph.weight > base.weight, pairs[i][1] + " should be heavier in the tokens");
            var fb = Type.font(base), fe = Type.font(emph);
            compare(fe.variableAxes.wght, emph.weight, pairs[i][1]);
            compare(fe.variableAxes.opsz, emph.size, pairs[i][1]);
            compare(fb.variableAxes.wght, base.weight, pairs[i][0]);
            var regular = textComp.createObject(root, { "font": fb });
            var emphasized = textComp.createObject(root, { "font": fe });
            regular.font.letterSpacing = 0;
            emphasized.font.letterSpacing = 0;
            verify(emphasized.implicitWidth > regular.implicitWidth,
                   pairs[i][1] + " width " + emphasized.implicitWidth + " should exceed " + regular.implicitWidth);
            regular.destroy();
            emphasized.destroy();
        }
    }

    // Pixels of ink: opaque and dark (works whether the grab background is white or transparent).
    function ink(item) {
        wait(60);
        var img = grabImage(item), n = 0;
        for (var y = 0; y < img.height; y++)
            for (var x = 0; x < img.width; x++)
                if (img.alpha(x, y) > 127 && img.red(x, y) < 128) n++;
        return n;
    }

    Component { id: iconComp; Icon {} }

    // The star is an outline at FILL 0 and a solid shape at FILL 1, so filling it must add ink.
    function test_icon_fill_axis_adds_ink_when_qt_supports_variable_axes() {
        if (paths.icons === undefined) skip("icon font not available");
        load(paths.icons);
        var probe = textComp.createObject(root, { "font.family": Fonts.iconFamily });
        var supported = probe.font.variableAxes !== undefined;
        probe.destroy();
        if (!supported)
            skip("this Qt has no font.variableAxes, so the FILL axis cannot be tested here");
        var outline = createTemporaryObject(iconComp, root, { name: "star", size: 96, fill: 0, color: "black", x: 0 });
        var solid = createTemporaryObject(iconComp, root, { name: "star", size: 96, fill: 1, color: "black", x: 100 });
        var a = ink(outline), b = ink(solid);
        verify(b > a * 1.3, "filled star ink " + b + " should clearly exceed outline star ink " + a);
        solid.fill = 0;
        compare(ink(solid), a, "setting fill back to 0 must restore the outline");
    }

    function test_icon_ligature_renders_a_glyph_not_the_word() {
        if (paths.icons === undefined) skip("icon font not available");
        load(paths.icons);
        var icon = textComp.createObject(root, { text: "settings", "font.family": Fonts.iconFamily, "font.pixelSize": 24 });
        var plain = textComp.createObject(root, { text: "settings", "font.family": "monospace", "font.pixelSize": 24 });
        // A ligature collapses the word to one square-ish glyph, far narrower than eight letters.
        verify(icon.implicitWidth < plain.implicitWidth * 0.5,
               "icon " + icon.implicitWidth + " vs word " + plain.implicitWidth);
        icon.destroy();
        plain.destroy();
    }
}
