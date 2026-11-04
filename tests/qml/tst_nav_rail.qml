// NavRail (plan 1.5, D103) offscreen against the Compose rail tokens: widths, the indicator and label, the active
// item's colors and grown indicator, clicks and keys reporting the choice without changing it, the header slot.
import QtQuick
import QtTest
import qs.common
import qs.components

TestCase {
    id: root
    name: "NavRail"
    width: 400
    height: 600
    visible: true
    when: windowShown

    readonly property var items: [{ id: "a", text: "Network", icon: "wifi" }, { id: "b", text: "Bluetooth", icon: "bluetooth" },
                                  { id: "c", text: "A very long destination name", icon: "info" }]
    Component { id: railComp; NavRail {} }
    Component { id: headerComp; NavRail { IconButton { objectName: "railMenu"; iconName: "menu" } } }
    Component { id: spyComp; SignalSpy {} }

    function init() { Motion.speed = 1; }
    function cleanup() { Motion.speed = 1; }
    function rail(props) {
        const r = createTemporaryObject(railComp, root, Object.assign({ items: items, currentId: "a" }, props || {}));
        waitForRendering(r);
        return r;
    }
    function pill(r, id) { return findChild(findChild(r, "navRail_" + id), "navRailPill"); }

    function test_sizes_from_the_tokens() {
        const spec = ControlSpec.navRailSpec;
        compare(rail().width, spec.collapsed.containerWidth);
        compare(spec.collapsed.containerWidth, 96);
        compare(rail({ narrow: true }).width, spec.collapsed.narrowContainerWidth);
        const r = rail();
        const ind = findChild(findChild(r, "navRail_a"), "navRailIndicator");
        compare([ind.width, ind.height].join(), [spec.item.activeIndicatorWidth, spec.item.activeIndicatorHeight].join());
        compare(ind.width, 56);
        const a = findChild(r, "navRail_a"), b = findChild(r, "navRail_b");
        compare(b.y - (a.y + a.height), spec.collapsed.itemVerticalSpace, "the items' spacing");
        const label = findChild(a, "navRailLabel");
        compare(label.y - (ind.y + ind.height), spec.item.iconLabelSpace);
        compare(label.font.pixelSize, Type.labelMedium.size);
        compare(a.mapToItem(r, 0, 0).y, spec.collapsed.topSpace, "the first destination the top space down");
    }

    function test_active_item() {
        const r = rail();
        const a = findChild(r, "navRail_a"), b = findChild(r, "navRail_b");
        compare(pill(r, "a").width, 56, "the active one's indicator, shown at once at first");
        verify(!pill(r, "b").visible, "the others have none");
        compare(pill(r, "a").color, Colors.secondaryContainer);
        compare(findChild(a, "navRailLabel").color, Colors.secondary);
        compare(findChild(b, "navRailLabel").color, Colors.surfaceVariantOn);
        verify(findChild(r, "navRail_c").children.length > 0);
        verify(findChild(findChild(r, "navRail_c"), "navRailLabel").truncated, "a long name is cut, not wider than the rail");
        // a new current one grows from its middle
        r.currentId = "b";
        tryVerify(() => pill(r, "b").width > 0 && pill(r, "b").width < 56, 1000, "growing");
        const p = pill(r, "b");
        fuzzyCompare(p.x + p.width / 2, 28, 0.5, "from the middle");
        tryCompare(p, "width", 56, 2000);
        tryVerify(() => !pill(r, "a").visible, 2000, "the old one shrinks away");
    }

    function test_choosing() {
        const r = rail();
        const chosen = createTemporaryObject(spyComp, root, { target: r, signalName: "chosen" });
        mouseClick(findChild(r, "navRail_b"));
        compare(chosen.signalArguments[0][0], "b");
        compare(r.currentId, "a", "the owner changes it, not the rail");
        const c = findChild(r, "navRail_c");
        c.forceActiveFocus();
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Space);
        compare(chosen.signalArguments.map(x => x[0]).join(), "b,c,c");
    }

    function test_header() {
        const r = createTemporaryObject(headerComp, root, { items: items, currentId: "a" });
        waitForRendering(r);
        const menu = findChild(r, "railMenu");
        verify(menu);
        const a = findChild(r, "navRail_a");
        verify(a.mapToItem(r, 0, 0).y > menu.mapToItem(r, 0, menu.height).y, "the destinations under the header");
        compare(menu.mapToItem(r, menu.width / 2, 0).x, r.width / 2, "centred");
    }
}
