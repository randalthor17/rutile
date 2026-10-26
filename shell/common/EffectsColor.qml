// The M3 effects spring for colors, as an animation: `Behavior on color { EffectsColor {} }`.
// Effects springs are critically damped, so a ColorAnimation on the equivalent curve
// (Motion.effects()) matches them. A Behavior on the property itself costs about a third of a
// separate animated-color object (measured with tools/dev/memcost.py).
import QtQuick

ColorAnimation {
    property string speed: "default"     // fast | default | slow
    duration: Motion.duration(Motion.effects(speed).duration)     // at Motion.speed (D43)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Motion.effects(speed).bezier
}
