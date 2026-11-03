// Fab and Card (plan 1.5) offscreen against the tokens: FAB sizes and shapes, the extended FAB's width from its
// spacing tokens and label, collapsing to the icon, colors, clicks; a card's colors, outline states and clicks
// only when interactive.
import QtQuick
import QtTest
import qs.common
import qs.components

TestCase {
    id: root
    name: "FabCard"
    width: 800
    height: 600
    visible: true
    when: windowShown

    Component { id: fabComp; Fab {} }
    Component { id: cardComp; Card { width: 200; height: 120 } }
    Component { id: spyComp; SignalSpy {} }

    function init() { Colors.mode = "dark"; }

    function test_fab_sizes() {
        for (const size of ["small", "baseline", "medium", "large"]) {
            const f = createTemporaryObject(fabComp, root, { size: size });
            const s = ControlSpec.fabSpec.sizes[size];
            compare(f.width, s.containerWidth, size);
            compare(f.height, s.containerHeight, size);
            compare(f.radius, s.containerShape, size);
        }
        compare(ControlSpec.fabSpec.sizes.medium.containerShape, Shapes.largeIncreased, "the medium FAB's corner (a TODO upstream)");
        const f = createTemporaryObject(fabComp, root, { variant: "secondary" });
        compare(f.color, Colors[ControlSpec.fabSpec.colors.secondary.containerColor]);
        compare(f.contentColor, Colors[ControlSpec.fabSpec.colors.secondary.iconColor]);
    }

    function test_extended_fab() {
        const f = createTemporaryObject(fabComp, root, { text: "Compose", iconName: "edit" });
        const e = ControlSpec.fabSpec.extended.small;
        const label = findChild(f, "fabLabel");
        tryCompare(f, "width", e.leadingSpace + e.iconSize + e.iconLabelSpace + label.implicitWidth + e.trailingSpace, 2000);
        compare(f.height, e.containerHeight);
        f.expanded = false;
        tryCompare(f, "width", f.collapsedWidth, 2000, "collapsed to its icon");
        tryCompare(label, "opacity", 0, 2000);
        const m = createTemporaryObject(fabComp, root, { size: "medium", text: "Compose" });
        compare(m.height, ControlSpec.fabSpec.extended.medium.containerHeight);
        compare(findChild(m, "fabLabel").font.pixelSize, Type.font(Type.titleLarge).pixelSize);
        const s = createTemporaryObject(fabComp, root, { size: "small", text: "No" });
        compare(s.width, ControlSpec.fabSpec.sizes.small.containerWidth, "a small FAB has no extended form");
    }

    function test_fab_click() {
        const f = createTemporaryObject(fabComp, root);
        const spy = createTemporaryObject(spyComp, root, { target: f, signalName: "clicked" });
        mouseClick(f);
        compare(spy.count, 1);
        f.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(spy.count, 2);
    }

    function test_cards() {
        for (const type of ["elevated", "filled", "outlined"]) {
            const c = createTemporaryObject(cardComp, root, { type: type });
            const s = ControlSpec.cardSpec[type];
            compare(c.color, Colors[s.containerColor], type);
            compare(c.radius, s.containerShape, type);
            compare(c.border.width, s.outlineWidth ?? 0, type);
        }
        const o = createTemporaryObject(cardComp, root, { type: "outlined", interactive: true });
        compare(o.border.color, Colors[ControlSpec.cardSpec.outlined.outlineColor]);
        o.enabled = false;
        compare(o.border.color, Qt.alpha(Colors[ControlSpec.cardSpec.outlined.disabledOutlineColor],
                                         ControlSpec.cardSpec.outlined.disabledOutlineOpacity));
    }

    function test_card_clicks_only_when_interactive() {
        const c = createTemporaryObject(cardComp, root);
        const spy = createTemporaryObject(spyComp, root, { target: c, signalName: "clicked" });
        mouseClick(c);
        compare(spy.count, 0);
        c.interactive = true;
        mouseClick(c);
        compare(spy.count, 1);
    }
}
