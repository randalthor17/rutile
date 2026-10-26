import QtQuick
import QtTest
import qs.common
import qs.components

// Tile, Chip and ListItem: sizes and colors from ControlSpec, interaction (repeated after the motion
// settles), and pixels through the software renderer.
TestCase {
    id: root
    name: "QsControls"
    width: 800
    height: 600
    visible: true
    when: windowShown

    Component { id: tileComp; Tile { x: 40; y: 40; width: 300; text: "Wi-Fi"; iconName: "wifi" } }
    Component { id: chipComp; Chip { x: 40; y: 160; text: "Chip" } }
    Component { id: listComp; ListItem { x: 40; y: 240; width: 400; text: "Item" } }
    Component { id: spyComp; SignalSpy {} }
    Component { id: switchComp; Switch {} }

    // A stand-in for a system setting: the controls bind to `on` and only `apply()` changes it, as a real
    // backend does once the setting took effect (D33).
    QtObject {
        id: backend
        property bool on: false
        property var asked: []
        function apply() { on = asked[asked.length - 1]; }
    }
    Component {
        id: boundComp
        Item {
            property alias tile: t
            property alias sw: s
            property alias chip: c
            Tile { id: t; x: 40; y: 40; width: 300; text: "Wi-Fi"; controlled: true; active: backend.on
                   onToggled: wanted => backend.asked.push(wanted) }
            Switch { id: s; x: 40; y: 140; controlled: true; checked: backend.on
                     onToggled: wanted => backend.asked.push(wanted) }
            Chip { id: c; x: 40; y: 200; type: "filter"; text: "On"; controlled: true; selected: backend.on
                   onToggled: wanted => backend.asked.push(wanted) }
        }
    }

    function init() { Colors.mode = "dark"; }
    function cleanup() { Colors.mode = "dark"; mouseMove(root, 790, 590); }

    function make(comp, props) { return createTemporaryObject(comp, root, props || {}); }
    function pixel(img, x, y) {
        return { r: img.red(x, y) / 255, g: img.green(x, y) / 255, b: img.blue(x, y) / 255 };
    }
    function near(c, d, tol) {
        return Math.abs(c.r - d.r) <= tol && Math.abs(c.g - d.g) <= tol && Math.abs(c.b - d.b) <= tol;
    }
    function settledAt(get, want) {
        tryVerify(function () { return Math.abs(get() - want) < 0.05; }, 4000, "expected " + want + ", got " + get());
    }

    // ---- Controlled controls show only the applied state ----
    function test_controlled_controls_wait_for_the_setting_to_apply() {
        backend.on = false;
        var b = make(boundComp);
        var controls = [[b.tile, "active", 200, 36], [b.sw, "checked", 26, 16], [b.chip, "selected", 10, 16]];
        for (var i = 0; i < controls.length; i++) {
            var c = controls[i][0], prop = controls[i][1], px = controls[i][2], py = controls[i][3];
            for (var round = 0; round < 2; round++) {
                var want = !backend.on;
                backend.asked = [];
                mouseClick(c, px, py);
                compare(backend.asked, [want], prop + ": asks for the other state");
                compare(c[prop], !want, prop + ": shows nothing until the setting applies");
                backend.apply();
                compare(c[prop], want, prop + ": follows the applied state (the binding survived)");
            }
            backend.asked = [];
            mouseClick(c, px, py);
            compare(c[prop], backend.on, prop + ": a change that never applies is never shown");
            backend.on = !backend.on;
            compare(c[prop], backend.on, prop + ": a change made elsewhere shows too");
        }
    }

    // ---- Tile ----
    function test_tile_sizes() {
        var spec = ControlSpec.tileSpec;
        var t = make(tileComp);
        compare(t.implicitHeight, spec.tileHeight);
        var small = make(tileComp, { iconOnly: true, width: undefined });
        compare(small.implicitWidth, spec.tileHeight, "a small tile is square");
    }

    function test_tile_click_toggles_both_ways_and_reshapes() {
        var spec = ControlSpec.tileSpec;
        var t = make(tileComp);
        var spy = make(spyComp, { target: t, signalName: "toggled" });
        compare(t.colorState, "inactive");
        for (var round = 0; round < 2; round++) {
            mouseClick(t, 200, 36);
            verify(t.active, "on, round " + round);
            compare(t.colorState, "active");
            compare(t.tileRadius, spec.activeTileCornerRadius);
            tryCompare(t.children[0], "radius", spec.activeTileCornerRadius, 2000);
            mouseClick(t, 200, 36);
            verify(!t.active, "off, round " + round);
            tryCompare(t.children[0], "radius", spec.inactiveCornerRadius, 2000);
        }
        compare(spy.count, 4);
        t.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(t.active);
    }

    function test_dual_target_tile_toggles_from_its_icon_and_opens_from_the_body() {
        var t = make(tileComp, { dualTarget: true });
        var body = make(spyComp, { target: t, signalName: "clicked" });
        var spec = ControlSpec.tileSpec;
        var iconX = spec.tilePadding + spec.toggleTargetSize / 2;
        mouseClick(t, 200, 36);
        compare(body.count, 1);
        verify(!t.active, "the body does not toggle a dual-target tile");
        mouseClick(t, iconX, 36);
        verify(t.active);
        compare(t.colorState, "activeDual");
        compare(body.count, 1, "the icon does not open details");
        mouseClick(t, iconX, 36);
        verify(!t.active);
    }

    function test_unavailable_and_disabled_tiles_ignore_input() {
        var t = make(tileComp, { available: false, dualTarget: true });
        mouseClick(t, 200, 36);
        mouseClick(t, ControlSpec.tileSpec.tilePadding + ControlSpec.tileSpec.toggleTargetSize / 2, 36);
        verify(!t.active, "neither the body nor the icon toggles an unavailable tile");
        compare(t.colorState, "unavailable");
        var d = make(tileComp, { enabled: false });
        mouseClick(d, 200, 36);
        verify(!d.active);
    }

    Component {
        id: mirroredTileComp
        Item {
            property alias tile: t
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            x: 40; y: 300; width: 300; height: 72
            Tile { id: t; width: 300; text: "Wi-Fi"; iconName: "wifi" }
        }
    }

    function test_tile_mirrors_for_right_to_left() {
        var spec = ControlSpec.tileSpec;
        var t = make(mirroredTileComp).tile;
        var iconTarget = t.children[2], labels = t.children[5];
        compare(iconTarget.x, t.width - spec.tilePadding - spec.toggleTargetSize, "the icon is on the right");
        compare(labels.x + labels.width, iconTarget.x - spec.tileArrangementPadding, "the labels end before it");
        compare(labels.children[0].effectiveHorizontalAlignment, Text.AlignRight, "Latin labels sit by the icon");
        compare(labels.children[1].effectiveHorizontalAlignment, Text.AlignRight);
        compare(make(tileComp, { secondaryText: "Home" }).children[5].children[1].effectiveHorizontalAlignment,
                Text.AlignLeft, "and on the left otherwise");
        var ltr = make(tileComp);
        compare(ltr.children[2].x, spec.tilePadding, "and on the left otherwise");
        var tall = make(tileComp, { height: 150 });
        compare(tall.children[2].y, (150 - spec.toggleTargetSize) / 2, "a taller tile keeps its content centered");
    }

    function test_tile_colors_follow_systemui() {
        var states = ControlSpec.tileSpec.states;
        var t = make(tileComp, { active: true });
        compare(t.backgroundColor.toString(), Colors[states.active.backgroundColor].toString());
        t.dualTarget = true;
        compare(t.backgroundColor.toString(), Colors[states.activeDual.backgroundColor].toString());
        t.active = false;
        compare(t.colorState, "inactiveDual");
    }

    function test_tile_pixels() {
        var t = make(tileComp, { active: true, dualTarget: true });
        tryVerify(function () {
            var img = grabImage(t);
            var spec = ControlSpec.tileSpec;
            return near(pixel(img, spec.tilePadding + 4, 36), Colors.primary, 3 / 255)        // icon target
                && near(pixel(img, 250, 36), Colors.surfaceVariant, 3 / 255);                   // tile body
        }, 3000, "dual-target active: primary icon target on a surfaceVariant tile");
    }

    // ---- Chip ----
    function test_chip_layout_follows_compose_spacing() {
        var spec = ControlSpec.chipSpec, impl = spec.impl;
        var plain = make(chipComp);
        compare(plain.implicitHeight, spec.assist.containerHeight);
        var labelW = plain.implicitWidth - 2 * impl.contentPadding - 2 * impl.gap;
        verify(labelW > 0);
        var withIcon = make(chipComp, { iconName: "event" });
        compare(withIcon.implicitWidth, plain.implicitWidth + spec.assist.iconSize, "assist: icon then the normal gap");
        var filter = make(chipComp, { type: "filter", iconName: "event" });
        compare(filter.implicitWidth, plain.implicitWidth + spec.filter.iconSize - impl.gap + impl.compactGap,
                "filter: the compact gap next to an icon");
    }

    function test_filter_chip_toggles_both_ways_and_shows_a_check() {
        var spec = ControlSpec.chipSpec.filter;
        var c = make(chipComp, { type: "filter" });
        var spy = make(spyComp, { target: c, signalName: "toggled" });
        compare(c.leadingName, "");
        compare(c.containerColor.a, 0, "unselected filter chips are outlined, not filled");
        for (var round = 0; round < 2; round++) {
            mouseClick(c);
            verify(c.selected);
            compare(c.leadingName, "check");
            compare(c.containerColor.toString(), Colors[spec.flatSelectedContainerColor].toString());
            compare(c.outlineWidth, spec.flatSelectedOutlineWidth);
            mouseClick(c);
            verify(!c.selected);
            compare(c.outlineWidth, spec.flatUnselectedOutlineWidth);
        }
        compare(spy.count, 4);
        var own = make(chipComp, { type: "filter", iconName: "event", selected: true });
        compare(own.leadingName, "event", "its own icon wins over the check");
    }

    function test_filter_chip_check_grows_in_and_out() {
        var impl = ControlSpec.chipSpec.impl, icon = ControlSpec.chipSpec.filter.iconSize;
        var c = make(chipComp, { type: "filter" });
        var w0 = c.implicitWidth;
        mouseClick(c);
        compare(c.leadingShown, 0, "not yet: it grows");
        compare(c.implicitWidth, w0);
        tryVerify(() => c.leadingShown > 0.2 && c.leadingShown < 0.8, 2000, "on its way");
        verify(findChild(c, "chipLeading").active);
        tryCompare(c, "leadingShown", 1, 3000, "settles");
        compare(c.implicitWidth, w0 + icon - impl.gap + impl.compactGap, "room for the check, compact gap");
        var label = findChild(c, "chipLabel");
        compare(label.x, impl.contentPadding + icon + impl.compactGap, "the label after the check");
        mouseClick(c);
        tryVerify(() => c.leadingShown < 0.8 && c.leadingShown > 0.2, 2000, "shrinks back");
        verify(findChild(c, "chipLeading").active, "the check stays while it shrinks");
        verify(label.x > impl.contentPadding + impl.gap && label.x < impl.contentPadding + icon + impl.compactGap,
               "the label follows it");
        tryCompare(c, "implicitWidth", w0, 3000);
        compare(label.x, impl.contentPadding + impl.gap);
        tryVerify(() => !findChild(c, "chipLeading").active, 1000, "the icon unloads");
        var on = make(chipComp, { type: "filter", selected: true });
        compare(on.leadingShown, 1, "starts selected: no motion");
        compare(on.implicitWidth, w0 + icon - impl.gap + impl.compactGap);
        var own = make(chipComp, { type: "filter", iconName: "event" });
        compare(own.leadingShown, 1, "its own icon never moves");
    }

    function test_assist_chip_clicks_without_selecting() {
        var c = make(chipComp);
        var spy = make(spyComp, { target: c, signalName: "clicked" });
        mouseClick(c);
        compare(spy.count, 1);
        verify(!c.selected, "an assist chip never selects");
        mouseClick(c);
        compare(spy.count, 2);
        compare(c.labelColor.toString(), Colors[ControlSpec.chipSpec.assist.labelTextColor].toString());
        var e = make(chipComp, { elevated: true });
        compare(e.outlineWidth, 0);
        compare(e.containerColor.toString(), Colors[ControlSpec.chipSpec.assist.elevatedContainerColor].toString());
    }

    function test_disabled_chip() {
        var spec = ControlSpec.chipSpec.filter;
        var c = make(chipComp, { type: "filter", enabled: false });
        mouseClick(c);
        verify(!c.selected);
        compare(c.labelColor.a, spec.disabledLabelTextOpacity);
    }

    function test_chip_pixels() {
        var c = make(chipComp, { type: "filter", selected: true });
        tryVerify(function () {
            return near(pixel(grabImage(c), c.width - 4, 16), Colors.secondaryContainer, 3 / 255);
        }, 3000, "selected filter chip is filled with secondaryContainer");
        var o = make(chipComp, { type: "filter", y: 220 });
        tryVerify(function () {
            return near(pixel(grabImage(o), Math.round(o.width / 2), 0), Colors.outlineVariant, 20 / 255);
        }, 3000, "unselected filter chip has an outlineVariant outline");
    }

    // ---- ListItem ----
    function test_list_heights() {
        var spec = ControlSpec.listSpec;
        compare(make(listComp).implicitHeight, spec.itemOneLineContainerHeight);
        compare(make(listComp, { supportingText: "more" }).implicitHeight, spec.itemTwoLineContainerHeight);
    }

    function test_list_shape_morphs_with_state_every_time() {
        var shapes = ControlSpec.listSpec.impl.shapes;
        var l = make(listComp);
        compare(l.radiusNow, shapes.rest);
        for (var round = 0; round < 2; round++) {
            mouseMove(l, 100, 28);
            settledAt(function () { return l.radiusNow; }, shapes.hovered);
            mousePress(l, 100, 28);
            settledAt(function () { return l.radiusNow; }, shapes.pressed);
            mouseRelease(l, 100, 28);
            mouseMove(root, 790, 590);
            l.focus = false;
            settledAt(function () { return l.radiusNow; }, shapes.rest);
        }
        l.selected = true;
        settledAt(function () { return l.radiusNow; }, shapes.selected);
    }

    function test_segmented_group_keeps_its_outer_corners() {
        var spec = ControlSpec.listSpec;
        var first = make(listComp, { position: "first" });
        var c = first.children[0];          // the container (Spring is not an Item)
        compare(c.topLeftRadius, spec.containerShape);
        compare(c.bottomLeftRadius, spec.impl.shapes.rest);
        var last = make(listComp, { position: "last", y: 320 });
        compare(last.children[0].bottomRightRadius, spec.containerShape);
        compare(last.children[0].topRightRadius, spec.impl.shapes.rest);
        var middle = make(listComp, { position: "middle", y: 400 });
        compare(middle.children[0].topLeftRadius, spec.impl.shapes.rest);
    }

    function test_list_click_and_trailing_control() {
        var l = make(listComp);
        var spy = make(spyComp, { target: l, signalName: "clicked" });
        mouseClick(l, 100, 28);
        compare(spy.count, 1);
        var sw = createTemporaryObject(switchComp, l);
        l.trailing = [sw];
        wait(50);
        var p = sw.mapToItem(l, sw.width / 2, sw.height / 2);
        mouseClick(l, p.x, p.y);
        verify(sw.checked, "the trailing switch gets its own click");
        compare(spy.count, 1, "and the item does not");
    }

    function test_list_selected_colors_and_pixels() {
        var spec = ControlSpec.listSpec;
        var l = make(listComp, { selected: true });
        compare(l.containerColor.toString(), Colors[spec.itemSelectedContainerColor].toString());
        compare(l.labelColor.toString(), Colors[spec.itemSelectedLabelTextColor].toString());
        tryVerify(function () {
            return near(pixel(grabImage(l), 380, 28), Colors.secondaryContainer, 3 / 255);
        }, 3000, "selected item is secondaryContainer");
    }
}
