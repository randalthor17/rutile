// An M3 Expressive linear progress indicator (determinate): the active indicator, a 4 px gap,
// the track and a stop dot at the end. `wavy` draws the indicator as a moving wave that flattens
// near 0 and 1, as Compose's LinearWavyProgressIndicator. Sizes and colors come from
// ControlSpec.progressSpec; progress changes follow Compose's ProgressAnimationSpec spring.
import QtQuick
import qs.common

Item {
    id: root

    property real value: 0        // 0..1
    property bool wavy: false
    property bool animated: true  // false: draw `value` at once

    readonly property var spec: ControlSpec.progressSpec
    readonly property var linear: spec.linear
    readonly property real progress: Math.max(0, Math.min(1, value))
    readonly property real progressNow: animated ? progressSpring.value : progress
    // The wave shows only between the two thresholds; its amplitude eases in and out.
    readonly property bool waveOn: wavy && progress > spec.impl.waveOnAbove && progress < spec.impl.waveOffFrom
    property real amplitude: 0    // 0..1 of linear.activeWaveAmplitude; animated
    property real phase: 0        // 0..1 of a wavelength

    implicitWidth: spec.impl.linearWidth
    implicitHeight: wavy ? linear.waveHeight : linear.height

    Accessible.role: Accessible.ProgressBar

    Spring {
        id: progressSpring
        target: root.progress
        stiffness: root.spec.impl.progressSpring.stiffness
        dampingRatio: root.spec.impl.progressSpring.dampingRatio
        restDelta: root.spec.impl.progressSpring.visibilityThreshold
    }
    Component.onCompleted: {
        progressSpring.rest();
        amplitude = waveOn ? 1 : 0;
    }

    onWaveOnChanged: {
        const ease = waveOn ? spec.impl.amplitudeIn : spec.impl.amplitudeOut;
        amplitudeAnim.stop();
        amplitudeAnim.to = waveOn ? 1 : 0;
        amplitudeAnim.duration = Motion[ease.duration];
        amplitudeAnim.easing.bezierCurve = Motion.easing[ease.easing];
        amplitudeAnim.start();
    }
    NumberAnimation {
        id: amplitudeAnim
        target: root
        property: "amplitude"
        easing.type: Easing.BezierSpline
    }

    // One wavelength per second, only while a wave is visible.
    FrameAnimation {
        running: root.wavy && root.amplitude > 0 && root.visible
        onTriggered: root.phase = (root.phase + frameTime * root.spec.impl.wavelengthsPerSecond) % 1
    }

    SpringColor { id: indicatorFade; target: Colors[root.spec.activeIndicatorColor] }
    SpringColor { id: trackFade; target: Colors[root.spec.trackColor] }
    SpringColor { id: stopFade; target: Colors[root.spec.stopColor] }

    Canvas {
        id: canvas
        anchors.fill: parent

        readonly property var inputs: [root.progressNow, root.amplitude, root.phase, root.wavy, indicatorFade.value,
                                       trackFade.value, stopFade.value, width, height]
        onInputsChanged: requestPaint()

        function stroke(ctx, x0, x1, y, w, color) {
            ctx.strokeStyle = color;
            ctx.lineWidth = w;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(x0, y);
            ctx.lineTo(x1, y);
            ctx.stroke();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const lin = root.linear;
            const w = lin.activeThickness;
            const y = height / 2;
            const cap = w / 2;                       // round caps reach this far past each end
            const p = root.progressNow;
            const end = p * width;
            // With round caps the gap grows by the stroke width, as in Compose.
            const gap = lin.trackActiveSpace + lin.trackThickness;

            const trackStart = end + Math.min(end, gap);
            if (trackStart < width)
                stroke(ctx, Math.min(trackStart + cap, width - cap), width - cap, y, lin.trackThickness, trackFade.value);

            if (end > 0) {
                const x1 = Math.max(cap, end - cap);
                const amp = lin.activeWaveAmplitude * root.amplitude;
                if (root.wavy && amp > 0) {
                    ctx.strokeStyle = indicatorFade.value;
                    ctx.lineWidth = w;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.beginPath();
                    const k = 2 * Math.PI / lin.activeWaveWavelength;
                    const shift = root.phase * 2 * Math.PI;
                    for (let x = cap; x <= x1; x += 1) {
                        const yy = y + amp * Math.sin(k * x - shift);
                        if (x === cap) ctx.moveTo(x, yy); else ctx.lineTo(x, yy);
                    }
                    ctx.lineTo(x1, y + amp * Math.sin(k * x1 - shift));
                    ctx.stroke();
                } else {
                    stroke(ctx, cap, x1, y, w, indicatorFade.value);
                }
            }

            // Stop dot: never larger than the track, inset by at most the trailing space.
            const size = Math.min(lin.stopSize, lin.trackThickness);
            const inset = Math.min((lin.trackThickness - size) / 2, root.spec.impl.stopTrailingSpaceMax);
            ctx.fillStyle = stopFade.value;
            ctx.beginPath();
            ctx.arc(width - size / 2 - inset, y, size / 2, 0, 2 * Math.PI);
            ctx.fill();
        }
    }
}
