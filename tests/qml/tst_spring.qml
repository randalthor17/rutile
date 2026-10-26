import QtQuick
import QtTest
import qs.common
import "../qs/common/SpringMath.js" as SpringMath

TestCase {
    name: "Spring"

    property var cases: readJson("../data/spring_cases.json")

    function readJson(rel) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }

    Spring { id: sp }

    function init() { sp.snap(0); sp.stiffness = 380; sp.dampingRatio = 0.8; }
    function cleanup() { sp.snap(0); Motion.speed = 1; }

    // Run synchronously so the frame driver cannot interleave with manual steps.
    function simulate(target, seconds, dt) {
        sp.target = target;
        var peak = sp.value, steps = 0;
        for (var t = 0; t < seconds && !sp.settled; t += dt) {
            sp.step(dt);
            steps++;
            if (sp.value > peak) peak = sp.value;
        }
        return { peak: peak, steps: steps };
    }

    // Motion.speed (D43) scales time: a step at speed 2 is a step twice as long at speed 1; 0 jumps.
    function test_speed_scales_time() {
        sp.target = 1;
        sp.step(0.02);
        var normal = { x: sp.value, v: sp.velocity };
        sp.snap(0);
        Motion.speed = 2;
        sp.target = 1;
        sp.step(0.01);
        compare(sp.value, normal.x, "half the wall time at twice the speed");
        compare(sp.velocity, normal.v);
        sp.snap(0);
        Motion.speed = 0;
        sp.target = 1;
        sp.step(0.001);
        compare(sp.value, 1, "speed 0: no motion, straight to the target");
        verify(sp.settled);
    }

    function test_durations_follow_the_speed() {
        compare(Motion.duration(300), 300);
        Motion.speed = 2;
        compare(Motion.duration(300), 150);
        compare(effectsComp.createObject(null).duration, Math.round(Motion.effects("default").duration / 2));
        compare(colorComp.createObject(null).duration, Math.round(Motion.effects("default").duration / 2));
        Motion.speed = 0.5;
        compare(Motion.duration(300), 600);
        Motion.speed = 0;
        compare(Motion.duration(300), 0);
        compare(effectsComp.createObject(null).duration, 0);
    }
    Component { id: effectsComp; EffectsNumber {} }
    Component { id: colorComp; EffectsColor {} }

    function test_js_matches_python_reference() {
        compare(cases.length, 240);
        for (var i = 0; i < cases.length; i++) {
            var c = cases[i];
            var r = SpringMath.evaluate(c.t, c.x0, c.v0, c.target, c.k, c.z);
            var tol = 1e-9 * (1 + Math.abs(c.x) + Math.abs(c.v));
            verify(Math.abs(r.x - c.x) < tol, "x " + JSON.stringify(c) + " got " + r.x);
            verify(Math.abs(r.v - c.v) < tol, "v " + JSON.stringify(c) + " got " + r.v);
        }
    }

    function test_degenerate_parameters_snap_to_target() {
        compare(SpringMath.evaluate(1, 0, 0, 5, 0, 0.8).x, 5);
        compare(SpringMath.evaluate(1, 0, 0, 5, -1, 0.8).x, 5);
        compare(SpringMath.evaluate(1, 0, 0, 5, 100, -0.1).x, 5);
    }

    function test_starts_settled_and_step_is_noop() {
        verify(sp.settled);
        sp.step(0.016);
        compare(sp.value, 0);
    }

    function test_converges_and_settles_exactly_on_target() {
        var r = simulate(1, 5, 1 / 240);
        verify(sp.settled);
        compare(sp.value, 1);
        compare(sp.velocity, 0);
        verify(r.steps < 5 * 240, "took the whole window");
    }

    function test_underdamped_spatial_overshoots_effects_does_not() {
        sp.stiffness = 800; sp.dampingRatio = 0.6;
        var a = simulate(1, 5, 1 / 480);
        verify(a.peak > 1.02, "expected overshoot, peak " + a.peak);
        sp.snap(0);
        sp.stiffness = 1600; sp.dampingRatio = 1;
        var b = simulate(1, 5, 1 / 480);
        verify(b.peak <= 1 + 1e-9, "critically damped overshot: " + b.peak);
    }

    function test_retarget_keeps_value_and_velocity() {
        sp.target = 1;
        for (var i = 0; i < 6; i++) sp.step(1 / 60);
        var v = sp.value, vel = sp.velocity;
        verify(vel > 0 && v > 0 && v < 1);
        sp.target = -1;
        compare(sp.value, v);
        compare(sp.velocity, vel);
        verify(!sp.settled);
        simulate(-1, 5, 1 / 240);
        compare(sp.value, -1);
    }

    function test_long_stall_is_clamped_to_max_step() {
        sp.target = 1;
        sp.step(10);
        var clamped = sp.value;
        sp.snap(0);
        sp.target = 1;
        sp.step(sp.maxStep);
        compare(sp.value, clamped);
        verify(!sp.settled);
    }

    function test_snap_resets_everything() {
        sp.target = 1;
        sp.step(0.05);
        sp.snap(7);
        compare(sp.value, 7);
        compare(sp.target, 7);
        compare(sp.velocity, 0);
        verify(sp.settled);
    }

    Item { id: driver; property real goal: 5 }
    Component { id: boundComp; Spring { target: driver.goal } }

    function test_rest_keeps_a_bound_target_snap_does_not() {
        driver.goal = 5;
        var bound = createTemporaryObject(boundComp, this);
        compare(bound.target, 5);
        bound.rest();
        compare(bound.value, 5);
        verify(bound.settled);
        driver.goal = 9;                    // the binding must still be alive
        compare(bound.target, 9);
        verify(!bound.settled);

        var snapped = createTemporaryObject(boundComp, this);
        snapped.snap(5);                    // documents the pitfall: assignment removes the binding
        driver.goal = 12;
        compare(snapped.target, 5);
        driver.goal = 5;
    }

    // Settling by itself must not break the binding either (the gallery's motion lanes only moved one way).
    function test_a_bound_target_still_follows_after_settling() {
        driver.goal = 0;
        var bound = createTemporaryObject(boundComp, this);
        for (var round = 1; round <= 3; round++) {
            driver.goal = round % 2;
            for (var i = 0; i < 2000 && !bound.settled; i++) bound.step(1 / 240);
            verify(bound.settled, "round " + round);
            compare(bound.value, driver.goal, "round " + round);
            compare(bound.target, driver.goal, "binding kept, round " + round);
        }
        driver.goal = 5;
    }

    function test_spring_created_at_rest_is_settled_in_any_assignment_order() {
        var a = Qt.createQmlObject('import qs.common; Spring { value: 1; target: 1 }', this);
        var b = Qt.createQmlObject('import qs.common; Spring { target: 1; value: 1 }', this);
        verify(a.settled);
        verify(b.settled);
        var moving = Qt.createQmlObject('import qs.common; Spring { target: 3 }', this);
        verify(!moving.settled);
        a.destroy();
        b.destroy();
        moving.destroy();
    }

    function test_defaults_follow_expressive_default_spatial() {
        var fresh = Qt.createQmlObject('import QtQuick; import qs.common; Spring {}', this);
        var want = Motion.spring("spatial", "default");
        compare(fresh.stiffness, want.stiffness);
        compare(fresh.dampingRatio, want.dampingRatio);
        fresh.destroy();
    }
}
