// A color that chases `target` with an M3 effects spring. Effects springs never overshoot,
// so the shown color always stays between the color it left and the one it is heading to.
// Retargeting mid-transition starts from the color currently shown.
import QtQuick

QtObject {
    id: root

    property color target: "transparent"
    readonly property color value: mix(from, to, progress.value)

    // Colors of the current transition (from -> to); progress runs 0 -> 1.
    property color from: target
    property color to: target
    property Spring progress: Spring {
        value: 1
        target: 1
        stiffness: Motion.spring("effects", "default").stiffness
        dampingRatio: Motion.spring("effects", "default").dampingRatio
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    // False while the object is being constructed, so the first target does not fade in from
    // transparent; it is simply the starting color.
    property bool ready: false
    Component.onCompleted: {
        from = target;
        to = target;
        progress.snap(1);
        ready = true;
    }

    onTargetChanged: {
        if (!ready) return;
        const shown = value;     // still computed from the old from/to, so this is what is on screen
        from = shown;
        to = target;
        progress.snap(0);
        progress.target = 1;
    }
}
