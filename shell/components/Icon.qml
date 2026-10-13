// A Material Symbols icon. Icons are ligatures: `name` ("settings", "home", ...) is the glyph.
// `fill` (0..1) and `weight` use the font's variation axes when this Qt supports
// font.variableAxes; older Qt falls back to the font's default axes.
import QtQuick
import qs.common

Text {
    id: root

    property string name: ""
    property real size: 24
    property real fill: 0
    property int weight: 400
    property real grade: 0

    text: name
    color: Colors.surfaceOn
    width: size
    height: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font.family: Fonts.iconFamily
    font.pixelSize: size

    // Native glyph rendering on purpose. Qt's default (distance-field) text mishandles the overlapping
    // contours of filled Material Symbols glyphs (FILL 1): the shape comes out with light holes and
    // streaks. CurveRendering leaves hairline seams. Reproduced on Qt 6.12 under OpenGL; see
    // tests/qml_gpu/tst_glyphs.qml, which checks it through the real scene graph.
    renderType: Text.NativeRendering

    // font.variableAxes exists only in recent Qt; the access is feature-detected on purpose, so the
    // "property not found" warning (true on Qt 6.4) is suppressed for this function only.
    // qmllint disable type
    function applyAxes() {
        if (root.font["variableAxes"] === undefined) return;
        root.font["variableAxes"] = ({
            "FILL": fill,
            "wght": weight,
            "GRAD": grade,
            "opsz": Math.max(Fonts.iconAxes.opsz.min, Math.min(Fonts.iconAxes.opsz.max, size))
        });
    }
    // qmllint enable type

    onFillChanged: applyAxes()
    onWeightChanged: applyAxes()
    onGradeChanged: applyAxes()
    onSizeChanged: applyAxes()
    Component.onCompleted: applyAxes()
}
