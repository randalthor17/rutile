// The one open and close motion for every popup, dropdown and menu (D43). The popup grows from `origin` (the corner
// or edge it opens from) on the default spatial spring and fades in on the effects curve; when `shown` turns false
// it shrinks and fades the same way and takes no input meanwhile. `hidden` fires as soon as the fade reaches 0, so
// the owner can unload it: the spring's tail (about 300 ms more at speed 1) would only move what can't be seen, and
// a full-screen popup would hold its window, and the blur behind it, that long for nothing.
// Motion.speed scales it like every other animation. A popup loaded on demand uses PopupLoader, which wraps this.
//     PopupMotion { target: panel; shown: root.open; origin: Item.TopRight; onHidden: ... }
import QtQuick
import qs.common

QtObject {
    id: root

    property Item target: null
    property bool shown: true
    property int origin: Item.Top
    // Scale at the start of opening and the end of closing; shared so every popup moves alike.
    readonly property real fromScale: 0.85

    readonly property real progress: spring.value
    readonly property bool settled: spring.settled
    // Something of the popup is still on screen (open, or on its way in or out).
    readonly property bool visible: shown || fade > 0

    signal hidden()

    // Created at 0 with target 1 when shown: it grows in.
    readonly property Spring spring: Spring {
        value: 0
        target: root.shown ? 1 : 0
    }

    // The fade never overshoots: the effects curve, not the spatial spring. Faded out while closing: done; the
    // spring rests where it was going, so the popup ends at its starting scale. It starts at 0 and gets its binding
    // once created: a Behavior does not animate a property's first value, so it would open at full opacity.
    property real fade: 0
    Behavior on fade { EffectsNumber {} }
    Component.onCompleted: fade = Qt.binding(() => shown ? 1 : 0)
    onFadeChanged: if (fade === 0 && !shown) finish()
    // Closed before it had begun to show: the fade will not change, so it is done on the next turn (unless it was
    // shown again meanwhile).
    onShownChanged: if (!shown && fade === 0) Qt.callLater(finish)
    function finish() {
        if (shown) return;
        spring.rest();
        hidden();
    }

    readonly property list<QtObject> bindings: [
        Binding { when: !!root.target; target: root.target; property: "scale"; value: root.fromScale + (1 - root.fromScale) * root.spring.value },
        Binding { when: !!root.target; target: root.target; property: "transformOrigin"; value: root.origin },
        Binding { when: !!root.target; target: root.target; property: "opacity"; value: root.fade },
        Binding { when: !!root.target; target: root.target; property: "enabled"; value: root.shown }
    ]
}
