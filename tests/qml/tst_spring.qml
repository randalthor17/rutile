import QtQuick
import QtTest
import "../imp"
import "../imp/SpringMath.js" as SpringMath

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
    function cleanup() { sp.snap(0); }

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

    function test_defaults_follow_expressive_default_spatial() {
        var fresh = Qt.createQmlObject('import QtQuick; import "../imp"; Spring {}', this);
        var want = Motion.spring("spatial", "default");
        compare(fresh.stiffness, want.stiffness);
        compare(fresh.dampingRatio, want.dampingRatio);
        fresh.destroy();
    }
}
