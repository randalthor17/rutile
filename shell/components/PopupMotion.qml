// The one open and close motion for every popup, dropdown and menu (D43). The popup grows from `origin` (the corner
// or edge it opens from) on the default spatial spring and fades in on the effects curve; when `shown` turns false
// it shrinks and fades the same way, takes no input meanwhile, and then `hidden` fires so the owner can unload it.
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
    readonly property bool visible: shown || !spring.settled

    signal hidden()

    // Created at 0 with target 1 when shown: it grows in.
    readonly property Spring spring: Spring {
        value: 0
        target: root.shown ? 1 : 0
        onSettledChanged: if (settled && !root.shown) root.hidden()
    }

    // The fade never overshoots: the effects curve, not the spatial spring.
    property real fade: shown ? 1 : 0
    Behavior on fade { EffectsNumber {} }

    readonly property list<QtObject> bindings: [
        Binding { when: !!root.target; target: root.target; property: "scale"; value: root.fromScale + (1 - root.fromScale) * root.spring.value },
        Binding { when: !!root.target; target: root.target; property: "transformOrigin"; value: root.origin },
        Binding { when: !!root.target; target: root.target; property: "opacity"; value: root.fade },
        Binding { when: !!root.target; target: root.target; property: "enabled"; value: root.shown }
    ]
}
