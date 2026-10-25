// The M3 effects spring for numbers (opacity and other values that must not overshoot), as an
// animation: `Behavior on opacity { EffectsNumber { speed: "fast" } }`. See EffectsColor.
import QtQuick

NumberAnimation {
    property string speed: "default"     // fast | default | slow
    duration: Motion.effects(speed).duration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Motion.effects(speed).bezier
}
