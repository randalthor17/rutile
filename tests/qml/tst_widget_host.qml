import QtQuick
import QtTest
import qs.common
import qs.widgethost
import "../qs/widgethost/WidgetSpec.js" as Spec

TestCase {
    id: root
    name: "WidgetHost"
    width: 400
    height: 800
    visible: true
    when: windowShown

    function readJson(rel) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }
    Component { id: hostComp; WidgetHost { width: 360 } }
    function host(spec, values) {
        const h = createTemporaryObject(hostComp, root, { spec: spec, values: values ?? {} });
        waitForRendering(h);
        return h;
    }
    function widget(rootNode) { return { version: 1, name: "Test", root: rootNode }; }
    // every Text under an item, by its text
    function texts(item, out) {
        out = out ?? [];
        if (item.text !== undefined && item.font !== undefined && item.visible) out.push(item);
        for (const c of item.children) texts(c, out);
        return out;
    }
    function textOf(item, t) { return texts(item).find(x => x.text === t) ?? null; }
    // every node of a type under an item (the WidgetNodes drawing it)
    function nodes(item, type, out) {
        out = out ?? [];
        if (item.node !== undefined && item.node?.type === type && item.depth !== undefined) out.push(item);
        for (const c of item.children) nodes(c, type, out);
        return out;
    }

    // ---- more height than the content (a desktop widget made taller, D83) ----
    function test_a_taller_host_stretches_the_blocks() {
        const tile = t => ({ type: "tile", tone: "primary_container", children: [{ type: "header", title: t }] });
        const spec = widget({ type: "column", children: [
            { type: "header", title: "Top" },
            { type: "row", children: [tile("a"), { type: "tile", tone: "secondary_container", children: [
                { type: "header", title: "b" }, { type: "header", title: "b2" }] }, { type: "chip", label: "c" }] },
            { type: "card", children: [{ type: "header", title: "Card" }] },
            { type: "chip", label: "End" }] });
        const h = host(spec);
        const natural = h.implicitHeight;
        h.height = natural + 200;
        waitForRendering(h);
        const card = nodes(h, "card")[0];
        fuzzyCompare(card.height, card.implicitHeight + 200, 1, "the last block takes the extra height");
        const end = textOf(h, "End");
        fuzzyCompare(end.mapToItem(h, 0, 0).y + end.height, h.height, ControlSpec.chipSpec.impl.contentPadding + 16,
                     "the chip after it is at the bottom");
        const tiles = nodes(h, "tile");
        compare(tiles.length, 2);
        compare(tiles[0].height, tiles[1].height, "tiles side by side are as tall as each other");
        verify(tiles[0].height > tiles[0].implicitHeight, "the shorter one stretched");
        const chip = nodes(h, "chip")[0];
        compare(chip.height, chip.implicitHeight, "a chip in the row keeps its height");
        h.height = natural;
        waitForRendering(h);
        fuzzyCompare(card.height, card.implicitHeight, 1, "back to its content");

        const plain = host(widget({ type: "column", children: [{ type: "header", title: "x" }, { type: "chip", label: "y" }] }));
        const before = textOf(plain, "y").mapToItem(plain, 0, 0).y;
        plain.height = plain.implicitHeight + 100;
        waitForRendering(plain);
        compare(textOf(plain, "y").mapToItem(plain, 0, 0).y, before, "no block: nothing moves, the space stays below");
        const lone = host(widget({ type: "card", children: [{ type: "header", title: "solo" }] }));
        lone.height = lone.implicitHeight + 50;
        waitForRendering(lone);
        fuzzyCompare(nodes(lone, "card")[0].height, lone.height, 1, "a card at the root fills the host");
    }

    // ---- WidgetSpec.js ----
    function test_resolve() {
        const v = { battery: { level: 80, charging: true }, weather: { now: { temp: -2.5 } }, cal: { names: ["a", "b"] } };
        compare(Spec.resolve("{{battery.level}}%", v), "80%");
        compare(Spec.resolve("{{ weather.now.temp }} out", v), "-2.5 out", "spaces inside the braces, nested fields");
        compare(Spec.resolve("{{battery.charging}}", v), "Yes");
        compare(Spec.resolve("{{cal.names}}", v), "a, b");
        compare(Spec.resolve("{{battery.missing}} / {{nope.x}}", v), Spec.MISSING + " / " + Spec.MISSING);
        compare(Spec.resolve("{{weather.now}}", v), Spec.MISSING, "an object is no text");
        compare(Spec.resolve("{{battery.constructor}} {{battery.toString}}", v), Spec.MISSING + " " + Spec.MISSING,
                "a function is no text either");
        compare(Spec.resolve("{{battery.level + 1}}", v), "{{battery.level + 1}}", "no expressions: not a binding");
        compare(Spec.resolve("plain", v), "plain");
        compare(Spec.bindingsOf("{{a.b}} and {{ c.d.e }}").join(), "a.b,c.d.e");
    }
    function test_progress_aspect_tones() {
        const v = { c: { r: 0.25, s: "0.5", big: 7, word: "half" } };
        compare(Spec.progress(0.4, v), 0.4);
        compare(Spec.progress("{{c.r}}", v), 0.25);
        compare(Spec.progress("{{c.s}}", v), 0.5);
        compare(Spec.progress("{{c.big}}", v), 1, "clamped");
        compare(Spec.progress("{{c.word}}", v), 0);
        compare(Spec.progress("{{c.none}}", v), 0);
        compare(Spec.aspect("16:9"), 9 / 16);
        compare(Spec.aspect("1:1"), 1);
        compare(Spec.aspect("0:3"), 9 / 16, "malformed: 16:9");
        compare(JSON.stringify(Spec.toneColors("surface_container_high")),
                '{"fill":"surfaceContainerHigh","on":"surfaceOn","variant":"surfaceVariantOn","tinted":false}');
        verify(Spec.toneColors("primary_container").tinted);
        compare(Spec.toneColors("primary").on, "primaryOn");
        compare(Spec.toneColors("tertiary_container").on, "tertiaryContainerOn");
        compare(Spec.toneColors("inverse_surface").on, "inverseOnSurface");
        compare(Spec.toneColors("background").on, "backgroundOn");
        // every tone the spec allows has colors that exist
        for (const t of ["background", "error_container", "inverse_surface", "primary", "primary_container", "secondary",
                         "secondary_container", "surface", "surface_bright", "surface_container", "surface_container_high",
                         "surface_container_highest", "surface_container_low", "surface_container_lowest", "surface_dim",
                         "surface_variant", "tertiary", "tertiary_container"]) {
            const c = Spec.toneColors(t);
            for (const k of ["fill", "on", "variant"])
                verify(Colors[c[k]] !== undefined, t + ": " + k + " " + c[k]);
        }
    }
    function test_problems() {
        compare(Spec.problems(widget({ type: "column", children: [{ type: "chip", label: "x" }] })).length, 0);
        compare(Spec.problems({ version: 2, name: "x", root: { type: "chip", label: "x" } })[0], "version 2, this shell reads 1");
        compare(Spec.problems(widget({ type: "row", children: [{ type: "chip", label: "a" }, { type: "map" }] })).join(),
                'root.children[1]: unknown type "map", left out');
        let deep = { type: "chip", label: "x" };
        for (let i = 0; i < Spec.MAX_DEPTH; i++) deep = { type: "column", children: [deep] };
        verify(Spec.problems(widget(deep)).join().indexOf("deeper than") > 0);
        compare(Spec.problems(null).join(), "not a widget");
    }

    // ---- rendering ----
    // The spec's examples draw, with their bindings filled, in the card's colors.
    function test_examples() {
        const weather = host(readJson("../data/widgets/weather.json"), { weather: { temperature: 21, high: 23, condition: "Clear" } });
        verify(weather.height > 0);
        compare(weather.problems.join(), "");
        compare(weather.bindings.join(), "weather.high,weather.low,weather.temperature,weather.condition,weather.wind");
        verify(textOf(weather, "Current Weather"), "the header");
        const value = textOf(weather, "21");
        verify(value, "the stat, filled");
        compare(value.color, Colors.surfaceOn, "on a surface card: surfaceOn");
        verify(textOf(weather, "°"));
        verify(textOf(weather, "High 23° · Low " + Spec.MISSING + "°"), "a missing value among others");
        verify(textOf(weather, "Clear"));
        // a picture: the placeholder until it loads, at its aspect
        const pic = host(widget({ type: "heroImage", source: "{{media.art}}", aspect: "16:9" }));
        const img = findChild(pic, "widgetImagePlaceholder");
        verify(img.visible, "no picture yet: the placeholder");
        fuzzyCompare(img.height, img.width * 9 / 16, 1, "16:9");

        const battery = host(readJson("../data/widgets/stat-card.json"), { battery: { level: 64 } });
        compare(textOf(battery, "64").color, Colors.secondaryContainerOn, "on secondary_container: its On color");
        const bar = findChild(battery, "widgetProgress");
        compare(bar.value, 0.8);
        compare(bar.indicatorShown, Colors.secondaryContainerOn, "on a tinted card: drawn in its On color, at once");
        compare(bar.trackShown, Qt.alpha(Colors.secondaryContainerOn, ControlSpec.stateOpacity.dragged), "a faint track");
        const plain = host(widget({ type: "card", children: [{ type: "progress", value: 0.5 }] }));
        compare(findChild(plain, "widgetProgress").indicatorShown, Colors.primary, "on a surface: the theme's");
        const countdown = host(readJson("../data/widgets/countdown.json"), { countdown: { remaining: 0.3 } });
        verify(findChild(countdown, "widgetProgress").wavy);
        compare(findChild(countdown, "widgetProgress").value, 0.3);
        const list = host(readJson("../data/widgets/list.json"), {});
        verify(textOf(list, Spec.MISSING), "no value yet: the dash");
        verify(textOf(host(readJson("../data/widgets/stat.json"), {}), Spec.MISSING));
    }
    function test_values_update() {
        const h = host(readJson("../data/widgets/stat-card.json"), { battery: { level: 10 } });
        verify(textOf(h, "10"));
        h.values = { battery: { level: 11 } };
        waitForRendering(h);
        verify(textOf(h, "11"), "a new value shows");
    }
    function test_layout() {
        const chip = n => ({ type: "chip", label: "c" + n });
        const head = n => ({ type: "header", title: "c" + n });
        const h = host(widget({ type: "column", spacing: "sm", children: [
            { type: "row", spacing: "md", children: [head(1), head(2), head(3)] },
            { type: "row", spacing: "sm", children: [chip(7), chip(8), head(9)] },
            { type: "grid", columns: 2, spacing: "xs", children: [chip(4), chip(5), chip(6)] },
            { type: "tile", tone: "primary", children: [{ type: "header", title: "On primary" }] }
        ] }));
        const c1 = textOf(h, "c1"), c2 = textOf(h, "c2"), c3 = textOf(h, "c3");
        const x = t => t.mapToItem(h, 0, 0).x, y = t => t.mapToItem(h, 0, 0).y;
        fuzzyCompare(x(c2) - x(c1), (360 + Spacing.md) / 3, 1, "a row: equal widths");
        fuzzyCompare(x(c3) - x(c2), (360 + Spacing.md) / 3, 1);
        compare(y(c1), y(c3), "side by side");
        // chips keep their own width, packed; the rest of the row is the header's
        const c7 = textOf(h, "c7"), c8 = textOf(h, "c8"), c9 = textOf(h, "c9");
        verify(x(c8) - x(c7) < 100, "packed: " + (x(c8) - x(c7)));
        verify(x(c9) - x(c8) < 100);
        const chipEnd = c8.parent.parent.mapToItem(h, c8.parent.parent.width, 0).x;
        fuzzyCompare(x(c9) - chipEnd, Spacing.sm, 1, "the header right after the chips");
        const c4 = textOf(h, "c4"), c5 = textOf(h, "c5"), c6 = textOf(h, "c6");
        fuzzyCompare(x(c5) - x(c4), (360 + Spacing.xs) / 2, 1, "a grid of 2");
        compare(x(c6), x(c4), "the third under the first");
        verify(y(c6) > y(c4));
        verify(y(c4) > y(c1), "stacked");
        compare(textOf(h, "On primary").color, Colors.primaryOn, "a tile's children in its On color");
        verify(h.height >= y(textOf(h, "On primary")), "the host's height covers its content");
    }
    function test_left_out() {
        const h = host(widget({ type: "column", children: [{ type: "map" }, { type: "chip", label: "still here" }] }));
        verify(textOf(h, "still here"), "the rest draws");
        compare(h.problems.length, 1);
        const other = host({ version: 2, name: "Future", root: { type: "chip", label: "x" } });
        compare(other.height, 0, "another version: nothing");
        verify(!textOf(other, "x"));
        compare(host(null).height, 0);
        // too deep: the deepest part is left out, the rest draws
        let deep = { type: "chip", label: "too deep" };
        for (let i = 0; i < Spec.MAX_DEPTH - 1; i++) deep = { type: "column", children: [deep] };
        verify(textOf(host(widget(deep)), "too deep"), "at the limit: drawn");
        const over = host(widget({ type: "column", children: [{ type: "chip", label: "shallow" }, deep] }));
        verify(textOf(over, "shallow"));
        verify(!textOf(over, "too deep"), "one level more: left out");
    }
}
