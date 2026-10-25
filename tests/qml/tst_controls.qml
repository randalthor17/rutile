import QtQuick
import QtTest
import qs.common
import qs.components

// Switch, Slider and ProgressBar: geometry and colors from ControlSpec, interaction, and pixels
// through the software renderer. Every interaction is repeated once the motion has settled.
TestCase {
    id: root
    name: "Controls"
    width: 800
    height: 600
    visible: true
    when: windowShown

    Component { id: switchComp; Switch { x: 40; y: 40 } }
    Component { id: sliderComp; Slider { x: 40; y: 120; width: 240 } }
    Component { id: progressComp; ProgressBar { x: 40; y: 200; width: 240 } }

    function init() { Colors.mode = "dark"; }
    function cleanup() { Colors.mode = "dark"; mouseMove(root, 700, 500); }

    function make(comp, props) { return createTemporaryObject(comp, root, props || {}); }
    function pixel(img, x, y) {
        return { r: img.red(x, y) / 255, g: img.green(x, y) / 255, b: img.blue(x, y) / 255 };
    }
    function near(c, d, tol) {
        return Math.abs(c.r - d.r) <= tol && Math.abs(c.g - d.g) <= tol && Math.abs(c.b - d.b) <= tol;
    }
    function settledAt(get, want) {
        tryVerify(function () { return Math.abs(get() - want) < 0.01; }, 4000, "expected " + want + ", got " + get());
    }

    // ---- Switch ----
    function test_switch_geometry_follows_the_tokens() {
        var spec = ControlSpec.switchSpec;
        var s = make(switchComp);
        compare(s.implicitWidth, spec.trackWidth);
        compare(s.implicitHeight, spec.trackHeight);
        compare(s.handleSizeNow, spec.unselectedHandleWidth, "starts settled");
        compare(s.handleXNow, (spec.trackHeight - spec.unselectedHandleWidth) / 2);
        var on = make(switchComp, { checked: true });
        compare(on.handleSizeNow, spec.selectedHandleWidth);
        compare(on.handleXNow + on.handleSizeNow, spec.trackWidth - (spec.trackHeight - spec.selectedHandleWidth) / 2,
                "same inset from the right as from the top");
        var icon = make(switchComp, { uncheckedIcon: "close" });
        compare(icon.handleSizeNow, spec.selectedHandleWidth, "an icon makes the off handle full size");
    }

    function test_switch_toggles_both_ways_by_click_and_key() {
        var s = make(switchComp);
        var spy = createTemporaryObject(spyComp, root, { target: s, signalName: "toggled" });
        for (var round = 0; round < 2; round++) {
            mouseClick(s);
            verify(s.checked, "on, round " + round);
            settledAt(function () { return s.handleXNow; }, s.handleX);
            mouseClick(s);
            verify(!s.checked, "off, round " + round);
            settledAt(function () { return s.handleXNow; }, s.handleX);
        }
        compare(spy.count, 4);
        s.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(s.checked);
        keyClick(Qt.Key_Return);
        verify(!s.checked);
    }
    Component { id: spyComp; SignalSpy {} }

    function test_switch_press_snaps_the_handle_large_and_release_springs_back() {
        var spec = ControlSpec.switchSpec;
        var s = make(switchComp);
        mousePress(s, 10, 16);
        compare(s.handleSizeNow, spec.pressedHandleWidth, "snaps, no animation while pressed");
        compare(s.handleXNow, spec.trackOutlineWidth);
        mouseRelease(s, 10, 16);
        verify(s.checked);
        settledAt(function () { return s.handleSizeNow; }, spec.selectedHandleWidth);
        mousePress(s, 10, 16);
        compare(s.handleSizeNow, spec.pressedHandleWidth, "again after settling");
        compare(s.handleXNow + s.handleSizeNow, spec.trackWidth - spec.trackOutlineWidth);
        mouseRelease(s, 10, 16);
    }

    function test_switch_colors_per_state() {
        var spec = ControlSpec.switchSpec;
        var s = make(switchComp);
        compare(s.trackColor.toString(), Colors[spec.unselectedTrackColor].toString());
        compare(s.outlineColor.toString(), Colors[spec.unselectedTrackOutlineColor].toString());
        compare(s.handleColor.toString(), Colors[spec.unselectedHandleColor].toString());
        mouseMove(s, 10, 16);
        tryCompare(s, "hovered", true);
        compare(s.handleColor.toString(), Colors[spec.unselectedHoverHandleColor].toString());
        s.checked = true;
        compare(s.trackColor.toString(), Colors[spec.selectedTrackColor].toString());
        compare(s.outlineColor.a, 0, "no outline when on");
        compare(s.handleColor.toString(), Colors[spec.selectedHoverHandleColor].toString());
        mouseMove(root, 700, 500);
        tryCompare(s, "hovered", false);
        compare(s.handleColor.toString(), Colors[spec.selectedHandleColor].toString());
    }

    function test_switch_disabled_ignores_input_and_uses_opaque_disabled_colors() {
        var spec = ControlSpec.switchSpec;
        var s = make(switchComp, { enabled: false });
        mouseClick(s);
        verify(!s.checked);
        var want = Qt.tint(Colors.surface, Qt.alpha(Colors[spec.disabledUnselectedHandleColor],
                                                    spec.disabledUnselectedHandleOpacity));
        verify(near(s.handleColor, want, 1 / 255));
        compare(s.handleColor.a, 1, "composited over the surface, not translucent");
    }

    function test_switch_pixels() {
        var s = make(switchComp, { checked: true });
        wait(50);
        var img = grabImage(s);
        verify(near(pixel(img, 8, 16), Colors.primary, 3 / 255), "track left of the handle");
        verify(near(pixel(img, 36, 16), Colors.primaryOn, 3 / 255), "handle");
        s.checked = false;
        settledAt(function () { return s.handleXNow; }, s.handleX);
        tryVerify(function () { return near(pixel(grabImage(s), 26, 1), Colors.outline, 12 / 255); }, 2000,
                  "outline at the top edge when off");
    }

    // A StateLayer driven by another MouseArea must not take the pointer itself.
    Component {
        id: layeredComp
        Item {
            width: 80; height: 40; x: 40; y: 300
            property alias under: under
            property alias stateLayer: layer
            MouseArea { id: under; anchors.fill: parent; hoverEnabled: true }
            StateLayer { id: layer; anchors.fill: parent; input: under }
        }
    }
    function test_statelayer_with_an_external_input_lets_the_pointer_through() {
        var it = make(layeredComp);
        var below = createTemporaryObject(spyComp, root, { target: it.under, signalName: "clicked" });
        var own = createTemporaryObject(spyComp, root, { target: it.stateLayer, signalName: "clicked" });
        mouseMove(it, 20, 20);
        tryCompare(it.stateLayer, "hovered", true);
        mouseClick(it, 20, 20);
        compare(below.count, 1, "the input area got the click");
        compare(own.count, 0);
    }

    // ---- Slider ----
    function test_slider_geometry() {
        var spec = ControlSpec.sliderSpec;
        var s = make(sliderComp);
        compare(s.implicitHeight, spec.handleHeight);
        compare(s.handleCenter, spec.handleWidth / 2, "value 0 at the start");
        s.value = 1;
        compare(s.handleCenter, s.width - spec.handleWidth / 2);
        s.value = 7;
        compare(s.handleCenter, s.width - spec.handleWidth / 2, "clamped for drawing");
    }

    function test_slider_click_and_drag_set_the_value_and_emit_moved() {
        var s = make(sliderComp);
        var spy = createTemporaryObject(spyComp, root, { target: s, signalName: "moved" });
        mouseClick(s, s.width / 2, 22);
        verify(Math.abs(s.value - 0.5) < 0.01, "value " + s.value);
        compare(spy.count, 1);
        mousePress(s, 20, 22);
        mouseMove(s, 200, 22);
        mouseMove(s, 400, 22);           // past the end: clamped
        mouseRelease(s, 400, 22);
        compare(s.value, 1);
        mouseClick(s, 2, 22);
        compare(s.value, 0);
    }

    function test_slider_steps_snap_and_keys_move() {
        var s = make(sliderComp, { from: 0, to: 10, stepSize: 2 });
        compare(s.stepCount, 5);
        mouseClick(s, s.width * 0.33, 22);
        compare(s.value, 4);
        keyClick(Qt.Key_Right);
        compare(s.value, 6);
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Left);
        compare(s.value, 2);
        keyClick(Qt.Key_End);
        compare(s.value, 10);
        keyClick(Qt.Key_Right);
        compare(s.value, 10, "stays at the end");
        keyClick(Qt.Key_Home);
        compare(s.value, 0);
    }

    function test_slider_handle_narrows_while_pressed_every_time() {
        var spec = ControlSpec.sliderSpec;
        var s = make(sliderComp);
        for (var round = 0; round < 2; round++) {
            mousePress(s, 100, 22);
            settledAt(function () { return s.handleWidthNow; }, spec.pressedHandleWidth);
            mouseRelease(s, 100, 22);
            s.focus = false;
            settledAt(function () { return s.handleWidthNow; }, spec.handleWidth);
        }
    }

    function test_slider_handle_narrows_with_keyboard_focus() {
        var spec = ControlSpec.sliderSpec;
        var s = make(sliderComp);
        s.forceActiveFocus();
        settledAt(function () { return s.handleWidthNow; }, spec.pressedHandleWidth);
        s.focus = false;
        settledAt(function () { return s.handleWidthNow; }, spec.handleWidth);
    }

    function test_slider_disabled_ignores_input() {
        var s = make(sliderComp, { enabled: false, value: 0.2 });
        mouseClick(s, 200, 22);
        compare(s.value, 0.2);
    }

    function test_slider_pixels_show_both_tracks_and_the_gap() {
        var s = make(sliderComp, { value: 0.5 });
        var c = Math.round(s.handleCenter);
        tryVerify(function () {
            var img = grabImage(s);
            return near(pixel(img, 30, 22), Colors.primary, 3 / 255)
                && near(pixel(img, 200, 22), Colors.secondaryContainer, 3 / 255);
        }, 2000, "active track primary, inactive secondaryContainer");
        var img = grabImage(s);
        verify(near(pixel(img, c, 22), Colors.primary, 3 / 255), "handle");
        var gap = pixel(img, c + 5, 22);
        verify(!near(gap, Colors.primary, 8 / 255) && !near(gap, Colors.secondaryContainer, 8 / 255),
               "gap beside the handle is empty: " + JSON.stringify(gap));
        verify(!near(pixel(img, 200, 4), Colors.secondaryContainer, 8 / 255), "track is 16 px, not full height");
        verify(near(pixel(img, 200, 22 - ControlSpec.sliderSpec.inactiveTrackHeight / 2 + 1), Colors.secondaryContainer, 3 / 255),
               "track reaches its top edge");
    }

    // ---- ProgressBar ----
    function test_progress_sizes_and_clamping() {
        var lin = ControlSpec.progressSpec.linear;
        var p = make(progressComp);
        compare(p.implicitHeight, lin.height);
        var w = make(progressComp, { wavy: true });
        compare(w.implicitHeight, lin.waveHeight);
        p.value = 3;
        compare(p.progress, 1);
        p.value = -1;
        compare(p.progress, 0);
    }

    function test_progress_animates_toward_new_values_without_overshoot() {
        var p = make(progressComp, { value: 0.2 });
        compare(p.progressNow, 0.2, "starts settled");
        p.value = 0.8;
        verify(p.progressNow < 0.8);
        var last = p.progressNow;
        tryVerify(function () {
            verify(p.progressNow >= last - 1e-9 && p.progressNow <= 0.8 + 1e-9, "monotonic, no overshoot");
            last = p.progressNow;
            return Math.abs(p.progressNow - 0.8) < 0.002;
        }, 6000);
        var q = make(progressComp, { value: 0.2, animated: false });
        q.value = 0.9;
        compare(q.progressNow, 0.9);
    }

    function test_progress_wave_shows_between_the_thresholds_and_moves() {
        var impl = ControlSpec.progressSpec.impl;
        var p = make(progressComp, { wavy: true, value: impl.waveOnAbove / 2 });
        verify(!p.waveOn);
        compare(p.amplitude, 0);
        p.value = 0.5;
        verify(p.waveOn);
        tryCompare(p, "amplitude", 1, 2000);
        var phase = p.phase;
        tryVerify(function () { return p.phase !== phase; }, 1000, "the wave moves");
        p.value = (impl.waveOffFrom + 1) / 2;
        verify(!p.waveOn);
        tryCompare(p, "amplitude", 0, 2000);
        p.value = 0.5;
        tryCompare(p, "amplitude", 1, 2000, "and back on");
        var flat = make(progressComp, { value: 0.5 });
        verify(!flat.waveOn, "only when wavy");
    }

    function test_progress_pixels() {
        var p = make(progressComp, { value: 0.5, animated: false });
        tryVerify(function () {
            var img = grabImage(p);
            return near(pixel(img, 60, 2), Colors.primary, 3 / 255)
                && near(pixel(img, 200, 2), Colors.secondaryContainer, 3 / 255);
        }, 2000, "indicator primary, track secondaryContainer");
        var img = grabImage(p);
        var gap = pixel(img, 124, 2);
        verify(!near(gap, Colors.primary, 8 / 255) && !near(gap, Colors.secondaryContainer, 8 / 255),
               "gap between indicator and track: " + JSON.stringify(gap));
        verify(near(pixel(img, 238, 2), Colors.primary, 20 / 255), "stop dot at the end");
    }
}
