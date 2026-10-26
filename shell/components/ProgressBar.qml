// An M3 Expressive linear progress indicator (determinate): the active indicator, a 4 px gap,
// the track and a stop dot at the end. `wavy` draws the indicator as a moving wave that flattens
// near 0 and 1, as Compose's LinearWavyProgressIndicator. Sizes and colors come from
// ControlSpec.progressSpec; progress changes follow Compose's ProgressAnimationSpec spring.
// Everything is a Rectangle except the wave, whose Canvas is only created while a wave shows.
pragma ComponentBehavior: Bound
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
        amplitudeAnim.duration = Motion.duration(Motion[ease.duration]);
        amplitudeAnim.easing.bezierCurve = Motion.easing[ease.easing];
        amplitudeAnim.start();
    }
    NumberAnimation {      // motion-speed: duration set through Motion.duration() above
        id: amplitudeAnim
        target: root
        property: "amplitude"
        easing.type: Easing.BezierSpline
    }

    // One wavelength per second at Motion.speed 1, only while a wave is visible.
    FrameAnimation {      // motion-speed: the phase advances by frameTime * Motion.speed
        running: root.wavy && root.amplitude > 0 && root.visible
        onTriggered: root.phase = (root.phase + frameTime * Motion.speed * root.spec.impl.wavelengthsPerSecond) % 1
    }

    property color indicatorShown: Colors[root.spec.activeIndicatorColor]
    Behavior on indicatorShown { EffectsColor {} }
    property color trackShown: Colors[root.spec.trackColor]
    Behavior on trackShown { EffectsColor {} }
    property color stopShown: Colors[root.spec.stopColor]
    Behavior on stopShown { EffectsColor {} }

    // Where things are drawn, in px. Round caps reach w/2 past each end of a stroke, so a stroke
    // from w/2 to end - w/2 is a pill from 0 to end; with them the gap grows by the stroke width.
    readonly property real end: progressNow * width
    readonly property real gap: linear.trackActiveSpace + linear.trackThickness
    readonly property real trackStart: end + Math.min(end, gap)

    Rectangle {
        id: track
        visible: root.trackStart < root.width - height
        x: root.trackStart
        width: Math.max(0, root.width - x)
        height: root.linear.trackThickness
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.trackShown
    }

    Rectangle {
        id: flatIndicator
        visible: root.end > 0 && !wave.active
        width: Math.max(height, root.end)
        height: root.linear.activeThickness
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.indicatorShown
    }

    // Stop dot: never larger than the track, inset by at most the trailing space.
    Rectangle {
        readonly property real inset: Math.min((root.linear.trackThickness - width) / 2, root.spec.impl.stopTrailingSpaceMax)
        width: Math.min(root.linear.stopSize, root.linear.trackThickness)
        height: width
        radius: width / 2
        x: root.width - width - inset
        anchors.verticalCenter: parent.verticalCenter
        color: root.stopShown
    }

    // The wave needs a path, so it is the one Canvas; it exists only while a wave is drawn.
    Loader {
        id: wave
        active: root.wavy && root.amplitude > 0 && root.end > 0
        anchors.fill: parent
        sourceComponent: Canvas {
            readonly property var inputs: [root.end, root.amplitude, root.phase, root.indicatorShown, width, height]
            onInputsChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const lin = root.linear;
                const w = lin.activeThickness;
                const cap = w / 2;
                const y = height / 2;
                const x1 = Math.max(cap, root.end - cap);
                const amp = lin.activeWaveAmplitude * root.amplitude;
                const k = 2 * Math.PI / lin.activeWaveWavelength;
                const shift = root.phase * 2 * Math.PI;
                ctx.strokeStyle = root.indicatorShown;
                ctx.lineWidth = w;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.beginPath();
                ctx.moveTo(cap, y + amp * Math.sin(k * cap - shift));
                for (let x = cap + 1; x < x1; x += 1)
                    ctx.lineTo(x, y + amp * Math.sin(k * x - shift));
                ctx.lineTo(x1, y + amp * Math.sin(k * x1 - shift));
                ctx.stroke();
            }
        }
    }
}
