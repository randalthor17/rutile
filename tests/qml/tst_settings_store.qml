import QtQuick
import QtTest
import "../qs/services/SettingsStore.js" as Store
import "../qs/services/SettingsSchema.js" as Schema

TestCase {
    name: "SettingsStore"

    readonly property var schema: ({
        type: "object",
        properties: {
            motion: { type: "object", properties: { speed: { type: "number", minimum: 0, maximum: 4, "default": 1 } } },
            shelf: { type: "object", properties: {
                pins: { type: "array", items: { type: "string" } },
                size: { type: "integer", "default": 48 },
                edge: { type: "string", "enum": ["bottom", "left"], "default": "bottom" },
                autohide: { type: "boolean", "default": false } } }
        }
    })

    function test_leaves() {
        compare(Object.keys(Store.leaves(schema)).join(), "motion.speed,shelf.pins,shelf.size,shelf.edge,shelf.autohide");
        compare(Store.leaves(Schema.schema)["motion.speed"]["default"], 1, "the shipped schema");
    }

    function test_valid() {
        const l = Store.leaves(schema);
        verify(Store.valid(l["motion.speed"], 0.5));
        verify(Store.valid(l["motion.speed"], 0), "the minimum is allowed");
        verify(Store.valid(l["motion.speed"], 4), "the maximum is allowed");
        verify(!Store.valid(l["motion.speed"], -0.1));
        verify(!Store.valid(l["motion.speed"], 4.1));
        verify(!Store.valid(l["motion.speed"], "1"));
        verify(!Store.valid(l["motion.speed"], NaN));
        verify(Store.valid(l["shelf.size"], 48));
        verify(!Store.valid(l["shelf.size"], 48.5), "integer");
        verify(Store.valid(l["shelf.edge"], "left"));
        verify(!Store.valid(l["shelf.edge"], "top"), "enum");
        verify(Store.valid(l["shelf.autohide"], true));
        verify(!Store.valid(l["shelf.autohide"], 1));
        verify(Store.valid(l["shelf.pins"], []));
        verify(Store.valid(l["shelf.pins"], ["foot"]));
        verify(!Store.valid(l["shelf.pins"], ["foot", 3]), "every item");
        verify(!Store.valid(l["shelf.pins"], "foot"));
    }

    function test_get() {
        const o = { motion: { speed: 2 }, list: [1], n: null };
        compare(Store.get(o, "motion.speed"), 2);
        compare(Store.get(o, "motion.other"), undefined);
        compare(Store.get(o, "motion.speed.deeper"), undefined);
        compare(Store.get(o, "list.0"), undefined, "not into arrays");
        compare(Store.get(o, "n.x"), undefined);
        compare(Store.get(o, "n"), null);
    }

    function test_with_value_keeps_the_rest() {
        const o = { note: "mine", motion: { speed: 2, future: true } };
        const c = Store.withValue(o, "motion.speed", 3);
        compare(JSON.stringify(c), '{"note":"mine","motion":{"speed":3,"future":true}}');
        compare(o.motion.speed, 2, "the original is not changed");
        compare(JSON.stringify(Store.withValue(o, "shelf.pins", ["a"])),
                '{"note":"mine","motion":{"speed":2,"future":true},"shelf":{"pins":["a"]}}', "objects are made");
        compare(JSON.stringify(Store.withValue({ shelf: 5 }, "shelf.pins", [])), '{"shelf":{"pins":[]}}',
                "a value in the way is replaced");
        compare(JSON.stringify(Store.withValue({ shelf: [1] }, "shelf.pins", [])), '{"shelf":{"pins":[]}}');
        compare(JSON.stringify(Store.withValue(null, "a", 1)), '{"a":1}');
    }

    function test_with_value_removes() {
        compare(JSON.stringify(Store.withValue({ motion: { speed: 2 }, x: 1 }, "motion.speed", undefined)), '{"x":1}',
                "an object left empty goes");
        compare(JSON.stringify(Store.withValue({ motion: { speed: 2, y: 1 } }, "motion.speed", undefined)),
                '{"motion":{"y":1}}');
        compare(JSON.stringify(Store.withValue({ x: 1 }, "motion.speed", undefined)), '{"x":1}', "nothing to remove");
        compare(JSON.stringify(Store.withValue({}, "a", null)), '{"a":null}', "null is a value");
    }

    function test_parse() {
        compare(JSON.stringify(Store.parse("").data), "{}");
        compare(JSON.stringify(Store.parse(" \n").data), "{}");
        compare(Store.parse('{"a": 1}').data.a, 1);
        verify(Store.parse("{oops").error !== undefined);
        verify(Store.parse("[1]").error !== undefined, "an array is not settings");
        verify(Store.parse("3").error !== undefined);
        verify(Store.parse("null").error !== undefined);
        compare(Store.parse('{"a": 1}').error, undefined);
    }

    function test_resolve_layers() {
        let r = Store.resolve(schema, {}, {});
        compare(r.values["motion.speed"], 1, "the default");
        compare(r.values["shelf.pins"], undefined, "no default: unset");
        compare(Object.keys(r.managed).length, 0);
        compare(r.problems.length, 0);

        r = Store.resolve(schema, { motion: { speed: 2 } }, {});
        compare(r.values["motion.speed"], 2, "the user's file beats the default");
        verify(!r.managed["motion.speed"]);

        r = Store.resolve(schema, { motion: { speed: 2 } }, { motion: { speed: 0.5 } });
        compare(r.values["motion.speed"], 0.5, "Nix beats the user's file");
        verify(r.managed["motion.speed"]);
        verify(!r.managed["shelf.size"]);

        r = Store.resolve(schema, {}, { motion: { speed: 0 } });
        compare(r.values["motion.speed"], 0, "a falsy value from Nix still counts");
        verify(r.managed["motion.speed"]);
    }

    function test_resolve_skips_bad_values() {
        let r = Store.resolve(schema, { motion: { speed: 9 } }, {});
        compare(r.values["motion.speed"], 1, "out of range: the default");
        compare(r.problems.length, 1);
        verify(r.problems[0].indexOf("settings.json: motion.speed: 9") === 0, r.problems[0]);

        r = Store.resolve(schema, { motion: { speed: 2 } }, { motion: { speed: "fast" } });
        compare(r.values["motion.speed"], 2, "a bad managed value does not hide the user's");
        verify(!r.managed["motion.speed"], "and is not managed");
        verify(r.problems[0].indexOf("managed.json: motion.speed") === 0, r.problems[0]);
    }

    function test_format() {
        compare(Store.format({ a: { b: 1 } }), '{\n  "a": {\n    "b": 1\n  }\n}\n');
    }
}
