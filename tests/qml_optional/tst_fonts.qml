import QtQuick
import QtTest
import qs.common

// Only part of the run when the real font files were found (see tools/qtws.py).
TestCase {
    id: root
    name: "FontFiles"

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

    // Type.font() sets wght/opsz through font.variableAxes where Qt has it; then the Emphasized
    // styles (weights 500/700) must come out wider than their regular twins.
    function test_emphasized_styles_render_heavier_when_qt_supports_variable_axes() {
        load(paths.text);
        var probe = textComp.createObject(root, { "font.family": Fonts.textFamily });
        var supported = probe.font.variableAxes !== undefined;
        probe.destroy();
        if (!supported)
            skip("this Qt has no font.variableAxes, so exact weights cannot be tested here");
        var pairs = [["bodyLarge", "bodyLargeEmphasized"], ["titleMedium", "titleMediumEmphasized"],
                     ["labelLarge", "labelLargeEmphasized"]];
        for (var i = 0; i < pairs.length; i++) {
            var regular = textComp.createObject(root, { "font": Type.font(Type[pairs[i][0]]) });
            var emphasized = textComp.createObject(root, { "font": Type.font(Type[pairs[i][1]]) });
            verify(emphasized.implicitWidth > regular.implicitWidth,
                   pairs[i][1] + " width " + emphasized.implicitWidth + " should exceed " + regular.implicitWidth);
            regular.destroy();
            emphasized.destroy();
        }
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
