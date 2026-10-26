// A Material 3 Expressive shape from the shape library (MaterialShapes.kt), filled with `color`.
// Setting `shape` to another name morphs to it with the fast spatial spring, as Compose's Morph
// does; a new shape mid-morph starts from the shape being left, not from the in-between outline.
// Names are MaterialShapes.names ("circle", "cookie9Sided", "softBurst", ...); an unknown name
// shows a circle and warns. Drawn with QtQuick.Shapes' curve renderer, so edges stay smooth at
// any size; the outline is rebuilt only while the morph runs or the size changes.
import QtQuick
import QtQuick.Shapes
import qs.common
import "../common/ShapeMath.js" as ShapeMath
import "../common/MaterialShapes.js" as MaterialShapes

Item {
    id: root

    property string shape: "circle"
    property color color: Colors.primary
    readonly property bool morphing: !spring.settled
    // The morph's progress from the shape being left (0) to `shape` (1); a spring, so it overshoots.
    readonly property real progress: spring.value

    // Idle, only names are kept; the curve pairs exist only while a morph runs (D31).
    property string _shown: ""
    property var _pairs: null

    function _polygon(name) {
        var def = MaterialShapes.shapes[name];
        if (!def) {
            console.warn("ShapeMorph: unknown shape", name);
            def = MaterialShapes.shapes.circle;
        }
        return ShapeMath.build(def);
    }

    onShapeChanged: {
        if (_shown === "" || _shown === shape) return;
        var pairs = ShapeMath.match(_polygon(_shown), _polygon(shape));
        // snap() settles the spring for a moment, which clears _pairs: set them after
        spring.snap(0);
        spring.target = 1;
        _shown = shape;
        _pairs = pairs;
    }
    onMorphingChanged: if (!morphing) _pairs = null

    Component.onCompleted: _shown = shape

    Spring {
        id: spring
        value: 1
        target: 1
        stiffness: Motion.spring("spatial", "fast").stiffness
        dampingRatio: Motion.spring("spatial", "fast").dampingRatio
    }

    Shape {
        objectName: "shapeMorphShape"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeWidth: -1
            PathSvg {
                path: root._shown === "" ? ""
                    : ShapeMath.svgPath(root._pairs ? ShapeMath.morph(root._pairs, spring.value)
                                                    : ShapeMath.outline(root._polygon(root._shown)),
                                        root.width, root.height)
            }
        }
    }
}
