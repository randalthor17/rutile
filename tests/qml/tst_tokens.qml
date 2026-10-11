import QtQuick
import QtTest
import qs.common

TestCase {
    name: "Tokens"

    property var tokens: readJson("../data/m3e.json")

    function readJson(rel) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }
    function camel(s) {
        return s.replace(/_([a-z0-9])/g, function (m, c) { return c.toUpperCase(); });
    }

    function test_corners_match_tokens() {
        var corners = tokens.shape.corner_dp;
        var n = 0;
        for (var name in corners) {
            var want = corners[name] === "full" ? 9999 : corners[name];
            compare(Shapes[camel(name)], want, name);
            n++;
        }
        compare(n, 10);
    }

    function test_elevation_matches_tokens() {
        var levels = tokens.elevation.dp;
        for (var name in levels)
            compare(Elevation[name], levels[name], name);
        compare(Elevation.level3, 6);
    }

    function test_durations_match_tokens() {
        var d = tokens.motion.duration_ms;
        var n = 0;
        for (var name in d) {
            compare(Motion[camel(name)], d[name], name);
            n++;
        }
        compare(n, 16);
    }

    function test_easing_is_bezier_spline_array() {
        var e = tokens.motion.easing_cubic_bezier;
        for (var name in e) {
            var got = Motion.easing[camel(name)];
            compare(got.length, 6, name);
            compare(JSON.stringify(got), JSON.stringify(e[name].concat([1, 1])), name);
        }
    }

    function test_springs_follow_scheme() {
        compare(Motion.scheme, "expressive");
        var f = Motion.spring("spatial", "fast");
        compare(f.stiffness, 800);
        compare(f.dampingRatio, 0.6);
        Motion.scheme = "standard";
        var g = Motion.spring("spatial", "fast");
        compare(g.stiffness, 1400);
        compare(g.dampingRatio, 0.9);
        Motion.scheme = "expressive";
    }

    function test_every_spring_matches_tokens() {
        var schemes = ["expressive", "standard"], axes = ["spatial", "effects"], speeds = ["fast", "default", "slow"];
        for (var i = 0; i < 2; i++) {
            Motion.scheme = schemes[i];
            for (var a = 0; a < 2; a++)
                for (var s = 0; s < 3; s++) {
                    var want = tokens.motion[schemes[i]][axes[a]][speeds[s]];
                    var got = Motion.spring(axes[a], speeds[s]);
                    compare(got.stiffness, want.stiffness);
                    compare(got.dampingRatio, want.damping_ratio);
                }
        }
        Motion.scheme = "expressive";
    }

    function test_type_styles_match_tokens() {
        var styles = tokens.type.styles;
        var n = 0;
        for (var name in styles) {
            var want = styles[name], got = Type[camel(name)];
            compare(got.size, want.size_sp, name);
            compare(got.lineHeight, want.line_height_sp, name);
            compare(got.tracking, want.tracking_sp, name);
            compare(got.weight, want.weight, name);
            compare(got.font, want.font, name);
            n++;
        }
        compare(n, 30);
        compare(Type.bodyLarge.size, 16);
        compare(Type.family(Type.displayLarge), Type.brandFamily);
        compare(Type.family(Type.bodyLarge), Type.plainFamily);
    }

    function test_fonts_singleton_and_type_defaults() {
        compare(Fonts.textFamily, "Google Sans Flex");
        compare(Fonts.iconFamily, "Material Symbols Rounded");
        compare(Type.plainFamily, Fonts.textFamily);
        compare(Type.brandFamily, Fonts.textFamily);
        compare(Fonts.textAxes.wght.min, 1);
        compare(Fonts.textAxes.wght.max, 1000);
        compare(Fonts.textAxes.ROND.max, 100);
        compare(Fonts.iconAxes.FILL.max, 1);
        compare(Object.keys(Fonts.textAxes).length, 6);
        compare(Object.keys(Fonts.iconAxes).length, 4);
    }

    function test_type_font_helper_matches_tokens() {
        var styles = tokens.type.styles;
        for (var name in styles) {
            var want = styles[name];
            var f = Type.font(Type[camel(name)]);
            compare(f.family, Fonts.textFamily, name);
            compare(f.pixelSize, want.size_sp, name);
            compare(f.weight, want.weight, name);
            // Qt keeps letter spacing in 1/64 px steps (0.15 reads back as 0.140625), so allow one step.
            fuzzyCompare(f.letterSpacing, want.tracking_sp, 1 / 64 + 1e-9, name);
        }
    }

    function test_style_names_list_every_token_style_in_order() {
        var want = Object.keys(tokens.type.styles).map(camel);
        compare(JSON.stringify(Type.styleNames), JSON.stringify(want));
        for (var i = 0; i < Type.styleNames.length; i++)
            verify(Type[Type.styleNames[i]].size > 0, Type.styleNames[i]);
    }

    function test_emphasized_styles_are_heavier_through_the_helper() {
        verify(Type.font(Type.titleMediumEmphasized).weight > Type.font(Type.titleMedium).weight);
        verify(Type.font(Type.bodyLargeEmphasized).weight > Type.font(Type.bodyLarge).weight);
    }

    function test_spacing_is_a_4px_grid() {
        var all = [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl];
        for (var i = 0; i < all.length; i++) {
            compare(all[i] % 4, 0);
            if (i > 0) verify(all[i] > all[i - 1]);
        }
        compare(Spacing.none, 0);
    }
}
