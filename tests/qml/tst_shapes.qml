import QtQuick
import QtTest
import qs.common
import qs.components
import "../qs/common/ShapeMath.js" as ShapeMath
import "../qs/common/MaterialShapes.js" as MaterialShapes

TestCase {
    id: root
    name: "Shapes"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component { id: morphComp; ShapeMorph { width: 100; height: 80 } }

    property var cases: readJson("../data/shape_cases.json")

    function readJson(rel) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }

    function sameCubics(got, want, what) {
        compare(got.length, want.length, what + ": curve count");
        for (var i = 0; i < want.length; i++)
            for (var k = 0; k < 8; k++)
                verify(Math.abs(got[i][k] - want[i][k]) < 1e-9,
                       what + " curve " + i + "[" + k + "]: " + got[i][k] + " vs " + want[i][k]);
    }

    function test_every_shape_matches_the_python_reference() {
        compare(MaterialShapes.names.length, 35);
        compare(Object.keys(cases.shapes).length, 35);
        for (var i = 0; i < MaterialShapes.names.length; i++) {
            var name = MaterialShapes.names[i];
            sameCubics(ShapeMath.outline(ShapeMath.build(MaterialShapes.shapes[name])), cases.shapes[name], name);
        }
    }

    function test_morphs_match_the_python_reference() {
        compare(cases.morphs.length, 9);
        for (var i = 0; i < cases.morphs.length; i++) {
            var m = cases.morphs[i];
            var pairs = ShapeMath.match(ShapeMath.build(MaterialShapes.shapes[m.from]),
                                        ShapeMath.build(MaterialShapes.shapes[m.to]));
            compare(pairs.length, m.count, m.from + " to " + m.to);
            for (var t in m.at)
                sameCubics(ShapeMath.morph(pairs, Number(t)), m.at[t], m.from + " to " + m.to + " at " + t);
        }
    }

    function test_svg_path_scales_the_unit_square() {
        var path = ShapeMath.svgPath([[0, 0, 0.25, 0, 0.75, 1, 1, 1]], 40, 20);
        compare(path, "M0 0C10 0 30 20 40 20Z");
        compare(ShapeMath.svgPath([], 40, 20), "");
        compare(ShapeMath.svgPath([[0.1234, 0, 0, 0, 0, 0, 0.5, 0.5]], 10, 10), "M1.23 0C0 0 0 0 5 5Z");
    }

    function test_unknown_kind_throws() {
        var threw = false;
        try { ShapeMath.build({ kind: "blob" }); } catch (e) { threw = true; }
        verify(threw);
    }

    function pathOf(item) {
        var shape = findChild(item, "shapeMorphShape");
        return shape.data[0].pathElements[0].path;
    }

    function springOf(item) {
        for (var i = 0; i < item.resources.length; i++)
            if (item.resources[i].stiffness !== undefined) return item.resources[i];
        return null;
    }

    function settle(item) {
        for (var i = 0; i < 400 && item.morphing; i++) springOf(item).step(0.016);
    }

    function test_shape_morph_draws_the_named_shape_at_its_size() {
        var m = createTemporaryObject(morphComp, root, { shape: "cookie9Sided" });
        verify(!m.morphing);
        compare(pathOf(m), ShapeMath.svgPath(ShapeMath.outline(ShapeMath.build(MaterialShapes.shapes.cookie9Sided)), 100, 80));
        compare(m.children[0].data[0].fillColor, Colors.primary);
        m.width = 50;
        compare(pathOf(m), ShapeMath.svgPath(ShapeMath.outline(ShapeMath.build(MaterialShapes.shapes.cookie9Sided)), 50, 80));
    }

    function test_changing_the_shape_morphs_with_a_spring() {
        var m = createTemporaryObject(morphComp, root, { shape: "circle" });
        var circle = pathOf(m);
        m.shape = "softBurst";
        verify(m.morphing);
        compare(m.progress, 0);
        var pairs = ShapeMath.match(ShapeMath.build(MaterialShapes.shapes.circle),
                                    ShapeMath.build(MaterialShapes.shapes.softBurst));
        compare(pathOf(m), ShapeMath.svgPath(ShapeMath.morph(pairs, 0), 100, 80));
        // the spring is the fast spatial one: it overshoots and settles quickly
        var spring = springOf(m);
        compare(spring.stiffness, Motion.spring("spatial", "fast").stiffness);
        compare(spring.dampingRatio, Motion.spring("spatial", "fast").dampingRatio);
        spring.step(0.05);
        verify(m.progress > 0 && m.progress < 1.2, m.progress);
        compare(pathOf(m), ShapeMath.svgPath(ShapeMath.morph(pairs, m.progress), 100, 80));
        verify(pathOf(m) !== circle);
        verify(m._pairs !== null);
        settle(m);
        verify(!m.morphing);
        compare(m.progress, 1);
        compare(m._pairs, null, "the curve pairs are dropped once the morph settles");
        compare(pathOf(m), ShapeMath.svgPath(ShapeMath.outline(ShapeMath.build(MaterialShapes.shapes.softBurst)), 100, 80));
    }

    function test_a_new_shape_mid_morph_starts_from_the_shape_being_left() {
        var m = createTemporaryObject(morphComp, root, { shape: "circle" });
        m.shape = "square";
        springOf(m).step(0.03);
        m.shape = "heart";
        compare(m.progress, 0);
        var pairs = ShapeMath.match(ShapeMath.build(MaterialShapes.shapes.square),
                                    ShapeMath.build(MaterialShapes.shapes.heart));
        compare(pathOf(m), ShapeMath.svgPath(ShapeMath.morph(pairs, 0), 100, 80));
    }

    function test_unknown_shape_warns_and_shows_a_circle() {
        ignoreWarning(new RegExp("ShapeMorph: unknown shape blob"));
        var m = createTemporaryObject(morphComp, root, { shape: "blob" });
        compare(pathOf(m), ShapeMath.svgPath(ShapeMath.outline(ShapeMath.build(MaterialShapes.shapes.circle)), 100, 80));
    }

    function test_shape_morph_is_idle_when_settled() {
        var m = createTemporaryObject(morphComp, root, { shape: "pill" });
        verify(springOf(m).settled);
        verify(!springOf(m).data[0].running, "no frame driver while idle");
    }
}
