import QtQuick
import QtTest
import qs.common
import qs.components

TestCase {
    id: root
    name: "Components"
    width: 800
    height: 600
    visible: true
    when: windowShown

    Component { id: buttonComp; Button {} }
    Component { id: iconButtonComp; IconButton {} }
    Component { id: stateComp; StateLayer { width: 80; height: 40 } }
    Component { id: surfaceComp; Surface { width: 60; height: 30 } }
    Component { id: colorComp; SpringColor {} }
    Component { id: iconComp; Icon {} }

    function init() { Colors.mode = "dark"; }
    function cleanup() { Colors.mode = "dark"; }

    function make(comp, props) { return createTemporaryObject(comp, root, props || {}); }
    function settle(spring) { for (var i = 0; i < 2000 && !spring.settled; i++) spring.step(1 / 240); }
    function rgbEqual(c, d, tol) {
        var t = tol === undefined ? 1 / 255 : tol;
        return Math.abs(c.r - d.r) <= t && Math.abs(c.g - d.g) <= t && Math.abs(c.b - d.b) <= t;
    }
    function px(v, h) { return v === "full" ? h / 2 : v; }

    // ---- SpringColor ----
    function test_springcolor_starts_at_its_target() {
        var c = make(colorComp, { target: "#336699" });
        compare(c.value.toString(), "#336699");
        verify(c.progress.settled);
    }

    function test_springcolor_does_not_fade_in_at_creation() {
        var c = make(colorComp, { target: "#336699" });
        wait(150);
        compare(c.value.toString(), "#336699");
        compare(c.value.a, 1);
        var s = make(surfaceComp);
        wait(150);
        compare(s.color.toString(), Colors.surfaceContainer.toString());
    }

    function test_springcolor_leaves_old_color_gradually_and_arrives_exactly() {
        var c = make(colorComp, { target: "#000000" });
        c.target = "#ffffff";
        compare(c.value.toString(), "#000000", "must not jump on retarget");
        var last = 0;
        for (var i = 0; i < 2000 && !c.progress.settled; i++) {
            c.progress.step(1 / 240);
            verify(c.value.r >= last - 1e-9, "red went backwards");
            verify(c.value.r <= 1 + 1e-9, "overshoot");
            last = c.value.r;
        }
        verify(c.progress.settled);
        compare(c.value.toString(), "#ffffff");
    }

    function test_springcolor_retarget_midway_starts_from_what_is_shown() {
        var c = make(colorComp, { target: "#000000" });
        c.target = "#ffffff";
        for (var i = 0; i < 8; i++) c.progress.step(1 / 120);
        var shown = c.value;
        verify(shown.r > 0.02 && shown.r < 0.98, "expected a mid transition, got " + shown.r);
        c.target = "#ff0000";
        verify(rgbEqual(c.value, shown, 1e-6), "color jumped on retarget");
        settle(c.progress);
        compare(c.value.toString(), "#ff0000");
    }

    // ---- Surface ----
    function test_surface_defaults_follow_tokens_and_animate_tone_changes() {
        var s = make(surfaceComp);
        compare(s.radius, Shapes.medium);
        compare(s.color.toString(), Colors.surfaceContainer.toString());
        s.tone = Colors.primary;
        compare(s.color.toString(), Colors.surfaceContainer.toString(), "jumped instead of animating");
    }

    // ---- Icon ----
    function test_icon_has_a_square_box_of_its_size_and_uses_the_icon_family() {
        var i = make(iconComp, { name: "home", size: 32 });
        compare(i.width, 32);
        compare(i.height, 32);
        compare(i.font.family, Fonts.iconFamily);
        compare(i.font.pixelSize, 32);
        i.fill = 1;
        i.weight = 300;
        compare(i.text, "home");
    }

    // ---- StateLayer ----
    function test_statelayer_target_opacity_follows_the_m3_state_opacities() {
        var s = make(stateComp);
        compare(s.targetOpacity, 0);
        s.focused = true;
        compare(s.targetOpacity, ControlSpec.stateOpacity.focus);
        s.dragged = true;
        compare(s.targetOpacity, ControlSpec.stateOpacity.dragged);
        s.dragged = false;
        s.enabled = false;
        compare(s.targetOpacity, 0);
    }

    function test_statelayer_hover_press_and_click() {
        var s = make(stateComp, { x: 10, y: 10 });
        var clicks = 0;
        s.clicked.connect(function () { clicks++; });
        mouseMove(s, 40, 20);
        tryCompare(s, "hovered", true);
        compare(s.targetOpacity, ControlSpec.stateOpacity.hover);
        mousePress(s, 40, 20);
        compare(s.targetOpacity, ControlSpec.stateOpacity.pressed);
        mouseRelease(s, 40, 20);
        compare(clicks, 1);
        tryVerify(function () { return Math.abs(s.opacityNow - ControlSpec.stateOpacity.hover) < 0.002; }, 3000);
    }

    // ---- Button: sizes ----
    function test_button_heights_and_paddings_follow_the_spec_for_every_size() {
        var sizes = Object.keys(ControlSpec.buttonSizes);
        compare(sizes.length, 5);
        for (var i = 0; i < sizes.length; i++) {
            var spec = ControlSpec.buttonSizes[sizes[i]];
            var b = make(buttonComp, { text: "Label", size: sizes[i] });
            compare(b.height, spec.height, sizes[i]);
            var textW = b.implicitWidth - spec.leading - spec.trailing;
            verify(textW > 10, sizes[i] + " label width " + textW);
            var withIcon = make(buttonComp, { text: "Label", iconName: "add", size: sizes[i] });
            compare(withIcon.implicitWidth, b.implicitWidth + spec.icon + spec.iconLabelGap, sizes[i]);
        }
    }

    function test_xs_button_uses_the_corrected_padding_and_gap() {
        var xs = ControlSpec.buttonSizes.xs;
        compare(xs.leading, 12);
        compare(xs.trailing, 12);
        compare(xs.iconLabelGap, 4);
        compare(ControlSpec.buttonSizes.s.leading, 16);
    }

    function test_icon_only_and_empty_buttons_size_sensibly() {
        var spec = ControlSpec.buttonSizes.m;
        var iconOnly = make(buttonComp, { iconName: "add", size: "m" });
        compare(iconOnly.implicitWidth, spec.leading + spec.icon + spec.trailing);
        var empty = make(buttonComp, { size: "m" });
        compare(empty.implicitWidth, spec.leading + spec.trailing);
    }

    // ---- Button: colors per type ----
    function test_button_type_colors_come_from_the_role_mapping() {
        var f = make(buttonComp, { text: "x", type: "filled" });
        compare(f.containerColor.toString(), Colors.primary.toString());
        compare(f.contentColor.toString(), Colors.primaryOn.toString());
        var t = make(buttonComp, { text: "x", type: "tonal" });
        compare(t.containerColor.toString(), Colors.secondaryContainer.toString());
        compare(t.contentColor.toString(), Colors.secondaryContainerOn.toString());
        var e = make(buttonComp, { text: "x", type: "elevated" });
        compare(e.containerColor.toString(), Colors.surfaceContainerLow.toString());
        compare(e.contentColor.toString(), Colors.primary.toString());
        var o = make(buttonComp, { text: "x", type: "outlined" });
        compare(o.containerColor.a, 0);
        verify(o.outlined);
        compare(o.outlineColor.toString(), Colors.outlineVariant.toString());
        compare(o.contentColor.toString(), Colors.surfaceVariantOn.toString());
        var x = make(buttonComp, { text: "x", type: "text" });
        compare(x.containerColor.a, 0);
        verify(!x.outlined);
        compare(x.contentColor.toString(), Colors.surfaceVariantOn.toString());
    }

    function test_button_colors_follow_the_theme_mode_with_animation() {
        var b = make(buttonComp, { text: "x", type: "filled" });
        var dark = b.containerNow.toString();
        Colors.mode = "light";
        compare(b.containerColor.toString(), Colors.primary.toString());
        compare(b.containerNow.toString(), dark, "must animate, not jump");
        tryVerify(function () { return b.containerNow.toString() === Colors.primary.toString(); }, 4000);
        verify(b.containerNow.toString() !== dark);
    }

    // ---- Button: interaction ----
    function test_click_emits_clicked_once() {
        var b = make(buttonComp, { text: "Go", x: 20, y: 20 });
        var n = 0;
        b.clicked.connect(function () { n++; });
        mouseClick(b, b.width / 2, b.height / 2);
        compare(n, 1);
    }

    function test_toggle_flips_checked_swaps_colors_and_emits_toggled() {
        var b = make(buttonComp, { text: "Tog", toggle: true, type: "filled", x: 20, y: 20 });
        var seen = [];
        b.toggled.connect(function (c) { seen.push(c); });
        compare(b.contentColor.toString(), Colors.surfaceVariantOn.toString());
        compare(b.containerColor.toString(), Colors.surfaceContainer.toString());
        mouseClick(b, b.width / 2, b.height / 2);
        verify(b.checked);
        compare(b.containerColor.toString(), Colors.primary.toString());
        compare(b.contentColor.toString(), Colors.primaryOn.toString());
        mouseClick(b, b.width / 2, b.height / 2);
        verify(!b.checked);
        compare(JSON.stringify(seen), "[true,false]");
    }

    function test_non_toggle_button_never_changes_checked() {
        var b = make(buttonComp, { text: "x", x: 20, y: 20 });
        mouseClick(b, b.width / 2, b.height / 2);
        verify(!b.checked);
    }

    function test_disabled_button_is_dimmed_and_ignores_clicks() {
        var b = make(buttonComp, { text: "No", type: "filled", enabled: false, x: 20, y: 20 });
        var n = 0;
        b.clicked.connect(function () { n++; });
        fuzzyCompare(b.containerColor.a, ControlSpec.stateOpacity.disabledContainer, 0.001);
        verify(rgbEqual(b.containerColor, Colors.surfaceOn));
        fuzzyCompare(b.contentColor.a, ControlSpec.stateOpacity.disabledContent, 0.001);
        mouseClick(b, b.width / 2, b.height / 2);
        compare(n, 0);
        var t = make(buttonComp, { text: "No", type: "text", enabled: false });
        compare(t.containerColor.a, 0);
    }

    function test_keyboard_activation_with_space_and_return() {
        var b = make(buttonComp, { text: "Key" });
        var n = 0;
        b.clicked.connect(function () { n++; });
        b.forceActiveFocus();
        verify(b.activeFocus);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_A);
        compare(n, 2);
    }

    // ---- Button: shape ----
    function test_round_and_square_rest_shapes() {
        for (var size in ControlSpec.buttonSizes) {
            var spec = ControlSpec.buttonSizes[size];
            var r = make(buttonComp, { text: "x", size: size, shape: "round" });
            compare(r.restRadius, r.height / 2, size);
            var q = make(buttonComp, { text: "x", size: size, shape: "square" });
            compare(q.restRadius, spec.shapeSquare, size);
            compare(q.radiusNow, spec.shapeSquare, "starts settled at rest: " + size);
        }
    }

    function test_press_morphs_the_shape_and_release_restores_it() {
        var b = make(buttonComp, { text: "Press", size: "m", x: 20, y: 20 });
        var rest = b.restRadius;
        var pressed = b.pressedRadius;
        verify(pressed < rest);
        compare(pressed, ControlSpec.buttonSizes.m.shapePressed);
        mouseMove(b, b.width / 2, b.height / 2);
        mousePress(b, b.width / 2, b.height / 2);
        tryVerify(function () { return Math.abs(b.radiusNow - pressed) < 0.6; }, 4000);
        mouseRelease(b, b.width / 2, b.height / 2);
        tryVerify(function () { return Math.abs(b.radiusNow - rest) < 0.6; }, 4000);
    }

    function test_selected_toggle_changes_rest_shape() {
        var b = make(buttonComp, { text: "x", toggle: true, size: "s", shape: "square" });
        compare(b.restRadius, ControlSpec.buttonSizes.s.shapeSquare);
        b.checked = true;
        compare(b.restRadius, px(ControlSpec.buttonSizes.s.shapeSelectedSquare, b.height));
    }

    // ---- IconButton ----
    function test_icon_button_widths_follow_the_spec() {
        for (var size in ControlSpec.iconButtonSizes) {
            var spec = ControlSpec.iconButtonSizes[size];
            var variants = ["default", "narrow", "wide"];
            for (var v = 0; v < 3; v++) {
                var b = make(iconButtonComp, { iconName: "add", size: size, widthVariant: variants[v] });
                compare(b.width, spec.width[variants[v]], size + "/" + variants[v]);
                compare(b.height, spec.height, size);
            }
            var d = make(iconButtonComp, { iconName: "add", size: size });
            compare(d.width, d.height, "default is square: " + size);
        }
    }

    function test_icon_button_type_colors() {
        var std = make(iconButtonComp, { iconName: "add", type: "standard" });
        compare(std.containerColor.a, 0);
        compare(std.contentColor.toString(), Colors.surfaceVariantOn.toString());
        var fil = make(iconButtonComp, { iconName: "add", type: "filled" });
        compare(fil.containerColor.toString(), Colors.primary.toString());
        compare(fil.contentColor.toString(), Colors.primaryOn.toString());
        var ton = make(iconButtonComp, { iconName: "add", type: "tonal" });
        compare(ton.containerColor.toString(), Colors.secondaryContainer.toString());
        var out = make(iconButtonComp, { iconName: "add", type: "outlined" });
        verify(out.outlined);
        compare(out.outlineColor.toString(), Colors.outlineVariant.toString());
    }

    function test_icon_button_toggle_swaps_round_and_square() {
        var spec = ControlSpec.iconButtonSizes.m;
        var round = make(iconButtonComp, { iconName: "star", size: "m", toggle: true, type: "filled", shape: "round" });
        compare(round.restRadius, round.height / 2);
        round.checked = true;
        compare(round.restRadius, spec.shapeSelectedRound);
        var square = make(iconButtonComp, { iconName: "star", size: "m", toggle: true, type: "filled", shape: "square" });
        compare(square.restRadius, spec.shapeSquare);
        square.checked = true;
        compare(square.restRadius, square.height / 2);
    }

    function test_icon_button_click_and_toggle() {
        var b = make(iconButtonComp, { iconName: "star", toggle: true, type: "tonal", x: 20, y: 20 });
        mouseClick(b, b.width / 2, b.height / 2);
        verify(b.checked);
        compare(b.containerColor.toString(), Colors.secondary.toString());
        compare(b.contentColor.toString(), Colors.secondaryOn.toString());
    }

    // ---- pixels (software renderer) ----
    function test_pixels_match_the_container_color_and_state_layer_blend() {
        var b = make(buttonComp, { text: "Pixel", type: "filled", size: "m", x: 40, y: 40 });
        wait(50);
        var img = grabImage(b);
        var x = 6, y = Math.round(b.height / 2);   // inside the pill, left of the label
        var want = Colors.primary;
        var c = { r: img.red(x, y) / 255, g: img.green(x, y) / 255, b: img.blue(x, y) / 255 };
        verify(rgbEqual(c, want, 3 / 255), "idle pixel " + JSON.stringify(c) + " vs " + want);
        mouseMove(b, b.width / 2, b.height / 2);
        tryVerify(function () { return Math.abs(b.hovered ? 1 : 0) === 1; }, 2000);
        tryVerify(function () { return Math.abs(b.children[2].opacityNow - ControlSpec.stateOpacity.hover) < 0.002; }, 4000);
        img = grabImage(b);
        var a = ControlSpec.stateOpacity.hover, on = Colors.primaryOn;
        var blend = { r: want.r + (on.r - want.r) * a, g: want.g + (on.g - want.g) * a, b: want.b + (on.b - want.b) * a };
        var h = { r: img.red(x, y) / 255, g: img.green(x, y) / 255, b: img.blue(x, y) / 255 };
        verify(rgbEqual(h, blend, 3 / 255), "hover pixel " + JSON.stringify(h) + " vs blend " + JSON.stringify(blend));
        mouseMove(root, 700, 500);
    }

    // grabImage may composite onto an opaque background (it does with the software renderer),
    // so shape is checked by color: corners show the background, the interior shows the container.
    function pixel(img, x, y) {
        return { r: img.red(x, y) / 255, g: img.green(x, y) / 255, b: img.blue(x, y) / 255 };
    }

    function test_pixels_round_button_has_empty_corners_and_a_filled_interior() {
        var b = make(buttonComp, { text: "Corner", type: "filled", size: "m", shape: "round", x: 40, y: 40 });
        wait(50);
        var img = grabImage(b);
        var fill = Colors.primary;
        verify(!rgbEqual(pixel(img, 0, 0), fill, 8 / 255), "corner is filled");
        verify(!rgbEqual(pixel(img, 6, 6), fill, 8 / 255), "pill corner area is filled");
        verify(rgbEqual(pixel(img, 6, Math.round(b.height / 2)), fill, 3 / 255), "interior is not the container color");
    }

    function test_pixels_square_button_fills_more_of_the_corner_than_a_round_one() {
        var b = make(buttonComp, { text: "Corner", type: "filled", size: "m", shape: "square", x: 40, y: 40 });
        wait(50);
        var img = grabImage(b);
        var fill = Colors.primary;
        // radius 16: (6,6) is inside the rounded corner; (0,0) is still outside it
        verify(rgbEqual(pixel(img, 6, 6), fill, 3 / 255), "(6,6) should be inside a 16px corner");
        verify(!rgbEqual(pixel(img, 0, 0), fill, 8 / 255), "(0,0) should be outside the corner");
    }

    function test_pixels_outlined_button_draws_its_outline_on_a_clear_container() {
        var b = make(buttonComp, { text: "Out", type: "outlined", size: "m", x: 40, y: 40 });
        wait(50);
        var img = grabImage(b);
        var edge = pixel(img, Math.round(b.width / 2), 0);    // top edge, middle: inside the outline
        verify(rgbEqual(edge, Colors.outlineVariant, 12 / 255), "outline not drawn: " + JSON.stringify(edge));
        var inner = pixel(img, 6, Math.round(b.height / 2));
        verify(!rgbEqual(inner, Colors.outlineVariant, 8 / 255), "interior should not be the outline color");
    }
}
