// A value that chases `target` with Material 3 spring motion.
// Use as `x: spring.value` and set `spring.target`. Retargeting mid-flight keeps
// the current value and velocity, so interrupted motion stays smooth.
import QtQuick
import "SpringMath.js" as SpringMath

QtObject {
    id: root

    property real value: 0
    property real target: 0
    property real velocity: 0

    // Default to the expressive "default spatial" spring; pass Motion.spring(...) values to change.
    property real stiffness: Motion.spring("spatial", "default").stiffness
    property real dampingRatio: Motion.spring("spatial", "default").dampingRatio

    property real restDelta: 0.001
    property real restVelocity: 0.01
    property bool settled: true

    // Longest step integrated at once, so a stalled frame does not make a visible jump.
    readonly property real maxStep: 0.064

    // Advance by dt seconds. Exposed so tests (and non-frame drivers) can step deterministically.
    function step(dt) {
        if (settled) return;
        var s = SpringMath.evaluate(Math.min(dt, maxStep), value, velocity, target, stiffness, dampingRatio);
        value = s.x;
        velocity = s.v;
        if (Math.abs(value - target) < restDelta && Math.abs(velocity) < restVelocity) {
            snap(target);
        }
    }

    // Jump to v with no motion.
    function snap(v) {
        target = v;
        value = v;
        velocity = 0;
        settled = true;
    }

    onTargetChanged: {
        if (value !== target) settled = false;
    }

    default property list<QtObject> data: [
        FrameAnimation {
            running: !root.settled
            onTriggered: root.step(frameTime)
        }
    ]
}
