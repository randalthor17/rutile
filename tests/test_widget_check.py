import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import widget_check as wc  # noqa: E402

ROLES = json.loads((ROOT / "theme" / "roles.json").read_text())["roles"]


def errors(value, schema):
    wc.check_keywords(schema)
    return wc.validate(value, schema, schema)


def ok(test, value, schema):
    test.assertEqual(errors(value, schema), [], f"{value!r} should match")


def bad(test, value, schema, needle):
    errs = errors(value, schema)
    test.assertTrue(errs, f"{value!r} should not match")
    test.assertTrue(any(needle in m for _, m in errs), f"{needle!r} not in {errs}")


def skeleton_spec():
    """A schema that satisfies the spec's structural rules with only a `type` per node.

    Built in code and deliberately not a usable widget spec (no node has its real fields), so the tests
    pin the checker without handing the widget-schema task its answer.
    """
    defs = {t: {"type": "object", "required": ["type"], "additionalProperties": False,
                "properties": {"type": {"const": t}}} for t in wc.NODE_TYPES}
    defs["card"]["properties"]["tone"] = {"$ref": "#/$defs/tone"}
    defs["tone"] = {"enum": ["surface_container", "primary_container"]}
    defs["node"] = {"oneOf": [{"$ref": f"#/$defs/{t}"} for t in wc.NODE_TYPES]}
    return {"$schema": wc.DRAFT, "type": "object", "required": ["version", "name", "root"],
            "additionalProperties": False, "$defs": defs,
            "properties": {"version": {"const": 1}, "name": {"type": "string"}, "root": {"$ref": "#/$defs/node"}}}


class Keywords(unittest.TestCase):
    def test_type_including_the_integer_and_boolean_traps(self):
        ok(self, 3, {"type": "integer"})
        bad(self, 3.5, {"type": "integer"}, "expected integer")
        bad(self, True, {"type": "integer"}, "expected integer")
        bad(self, True, {"type": "number"}, "expected number")
        ok(self, None, {"type": ["string", "null"]})
        bad(self, [], {"type": "object"}, "expected object")

    def test_a_wrong_type_is_one_error_not_a_cascade(self):
        # A model fixes the first line it reads; follow-on errors about a value of the wrong type mislead it.
        s = {"type": "string", "enum": ["a"], "minLength": 3, "pattern": "^x"}
        self.assertEqual(errors(5, s), [((), "expected string, got 5")])

    def test_enum_const_and_strings(self):
        ok(self, "a", {"enum": ["a", "b"]})
        bad(self, "c", {"enum": ["a", "b"]}, "is not one of")
        bad(self, 2, {"const": 1}, "must be 1")
        bad(self, "", {"type": "string", "minLength": 1}, "shorter")
        bad(self, "abcd", {"type": "string", "maxLength": 3}, "longer")
        ok(self, "timer", {"pattern": "^[a-z_]+$"})
        bad(self, "Timer!", {"pattern": "^[a-z_]+$"}, "does not match")

    def test_numbers(self):
        s = {"type": "number", "minimum": 0, "maximum": 1}
        ok(self, 0, s)
        ok(self, 1, s)
        bad(self, 1.5, s, "maximum")
        bad(self, -0.1, s, "minimum")
        bad(self, 0, {"exclusiveMinimum": 0}, "exclusiveMinimum")

    def test_objects_required_and_unknown_fields(self):
        s = {"type": "object", "required": ["a"], "properties": {"a": {"type": "string"}}, "additionalProperties": False}
        ok(self, {"a": "x"}, s)
        bad(self, {}, s, "missing required field 'a'")
        bad(self, {"a": "x", "b": 1}, s, "unknown field 'b' (allowed here: a)")
        bad(self, {"a": 1}, s, "expected string")
        ok(self, {"a": "x", "b": 1}, {"properties": {"a": {}}})
        bad(self, {"b": 1}, {"additionalProperties": {"type": "string"}}, "expected string")

    def test_arrays(self):
        s = {"type": "array", "items": {"type": "integer"}, "minItems": 1, "maxItems": 2}
        ok(self, [1, 2], s)
        bad(self, [], s, "at least 1")
        bad(self, [1, 2, 3], s, "at most 2")
        errs = errors([1, "x"], s)
        self.assertEqual(wc.path_str(errs[0][0]), "$[1]")

    def test_refs_and_combinators(self):
        s = {"$defs": {"n": {"type": "integer"}}, "$ref": "#/$defs/n"}
        ok(self, 1, s)
        bad(self, "x", s, "expected integer")
        bad(self, 5, {"oneOf": [{"type": "integer"}, {"type": "number"}]}, "matches 2 of the oneOf")
        bad(self, "x", {"oneOf": [{"type": "integer"}, {"type": "number"}]}, "expected")
        ok(self, "x", {"anyOf": [{"type": "integer"}, {"type": "string"}]})
        bad(self, None, {"anyOf": [{"type": "integer"}, {"type": "string"}]}, "expected")
        bad(self, 5, {"allOf": [{"type": "integer"}, {"maximum": 3}]}, "maximum")
        bad(self, 5, {"not": {"type": "integer"}}, "must not match")

    def test_if_then_else(self):
        s = {"if": {"properties": {"k": {"const": "a"}}}, "then": {"required": ["x"]}, "else": {"required": ["y"]}}
        ok(self, {"k": "a", "x": 1}, s)
        bad(self, {"k": "a"}, s, "'x'")
        bad(self, {"k": "b"}, s, "'y'")

    def test_unsupported_keywords_are_refused_not_ignored(self):
        for kw in ("prefixItems", "unevaluatedProperties", "patternProperties", "$dynamicRef", "dependentRequired"):
            with self.assertRaises(wc.SchemaError, msg=kw) as cm:
                wc.check_keywords({"properties": {"a": {kw: {}}}})
            self.assertIn(kw, str(cm.exception))
            self.assertIn("$.properties.a", str(cm.exception))

    def test_bad_refs_are_schema_errors(self):
        with self.assertRaises(wc.SchemaError):
            errors(1, {"$ref": "#/$defs/missing"})
        with self.assertRaises(wc.SchemaError):
            errors(1, {"$ref": "https://example.com/s.json"})

    def test_a_ref_loop_ends_with_an_error_instead_of_hanging(self):
        s = {"$defs": {"a": {"$ref": "#/$defs/a"}}, "$ref": "#/$defs/a"}
        self.assertTrue(any("too deep" in m for _, m in errors(1, s)))


class SpecRules(unittest.TestCase):
    def test_the_skeleton_satisfies_every_rule(self):
        self.assertEqual(wc.spec_rule_problems(skeleton_spec(), ROLES), [])

    def rule_errors(self, mutate):
        s = skeleton_spec()
        mutate(s)
        return [m for _, m in wc.spec_rule_problems(s, ROLES)]

    def test_each_rule_catches_its_violation(self):
        cases = {
            "must be 'https://json-schema.org/draft/2020-12/schema'": lambda s: s.update({"$schema": "draft-07"}),
            "no subschema for node type 'chip'": lambda s: s["$defs"].pop("chip"),
            "node 'stat': needs \"additionalProperties\": false": lambda s: s["$defs"]["stat"].pop("additionalProperties"),
            "tone must be restricted with an enum": lambda s: s["$defs"].update({"tone": {"type": "string"}}),
            "not in theme/roles.json: primary_box": lambda s: s["$defs"]["tone"]["enum"].append("primary_box"),
            "node type 'slider' is not in the spec": lambda s: s["$defs"].update(
                {"slider": {"properties": {"type": {"const": "slider"}}, "additionalProperties": False}}),
        }
        for needle, mutate in cases.items():
            errs = self.rule_errors(mutate)
            self.assertTrue(any(needle in e for e in errs), f"{needle!r} not in {errs}")

    def test_an_inline_tone_is_checked_too(self):
        errs = self.rule_errors(lambda s: s["$defs"]["card"]["properties"].update({"tone": {"enum": ["blue"]}}))
        self.assertTrue(any("blue" in e for e in errs), errs)


class Bindings(unittest.TestCase):
    def test_allowed_and_refused_bindings(self):
        good = {"a": "{{weather.temperature}}°", "b": ["{{ clock.time }}", "plain"], "c": {"d": "{{http.data.price}}"}}
        self.assertEqual(wc.binding_problems(good), [])
        for text in ("{{todo.title}}", "{{weather}}", "{{weather.temp + 1}}", "{{clock.time()}}", "{{ }}"):
            probs = wc.binding_problems({"t": text})
            self.assertEqual(len(probs), 1, text)
            self.assertEqual(wc.path_str(probs[0][0]), "$.t")


class Nodes(unittest.TestCase):
    def test_a_node_error_names_the_branch_for_its_type(self):
        s = skeleton_spec()
        errs = wc.validate({"version": 1, "name": "w", "root": {"type": "card", "tone": "blue"}}, s, s)
        self.assertEqual(len(errs), 1, errs)
        self.assertEqual(wc.path_str(errs[0][0]), "$.root.tone")
        self.assertIn("is not one of", errs[0][1])
        errs = wc.validate({"version": 1, "name": "w", "root": {"type": "slider"}}, s, s)
        self.assertIn("no node type \"slider\"", errs[0][1])


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.schema = self.tmp / "s.json"
        self.schema.write_text(json.dumps(skeleton_spec()))

    def run_main(self, *args):
        out = io.StringIO()
        code = wc.main(["--schema", str(self.schema), *map(str, args)], out=out)
        return code, out.getvalue()

    def widget(self, name, value):
        p = self.tmp / name
        p.write_text(value if isinstance(value, str) else json.dumps(value))
        return p

    def test_exit_codes_and_one_line_per_problem(self):
        good = self.widget("g.json", {"version": 1, "name": "g", "root": {"type": "chip"}})
        code, out = self.run_main(good)
        self.assertEqual(code, 0, out)
        self.assertIn("ok:", out)
        broken = self.widget("b.json", "{not json")
        wrong = self.widget("w.json", {"version": 2, "name": "w", "root": {"type": "chip", "x": 1}})
        code, out = self.run_main(broken, wrong)
        self.assertEqual(code, 1)
        self.assertIn("b.json: $: not valid JSON", out)
        self.assertIn("w.json: $.version: must be 1", out)
        self.assertIn("w.json: $.root: unknown field 'x'", out)

    def test_output_is_capped_per_file(self):
        many = self.widget("m.json", {"version": 1, "name": "m", "root": {"type": "chip", **{f"f{i}": 1 for i in range(40)}}})
        code, out = self.run_main(many)
        self.assertEqual(code, 1)
        self.assertEqual(sum(1 for l in out.splitlines() if "unknown field" in l), wc.MAX_PER_FILE)
        self.assertIn(f"and {40 - wc.MAX_PER_FILE} more", out)

    def test_an_unusable_schema_is_reported_not_crashed_on(self):
        self.schema.write_text(json.dumps({"$schema": wc.DRAFT, "prefixItems": []}))
        code, out = self.run_main(self.widget("g.json", {}))
        self.assertEqual(code, 1)
        self.assertIn("unsupported keyword(s) prefixItems", out)

    def test_runs_as_a_script_with_only_the_standard_library(self):
        p = subprocess.run([sys.executable, "-I", "-S", str(ROOT / "tools" / "widget_check.py"), "--schema",
                            str(self.schema), str(self.widget("g.json", {"version": 1, "name": "g", "root": {"type": "row"}}))],
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)


class Templates(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, True)

    def write_all(self):
        """30 templates with distinct structures (a column of k chips) and a binding each."""
        k = 0
        for c in wc.TEMPLATE_CATEGORIES:
            for n in range(1, wc.TEMPLATES_PER_CATEGORY + 1):
                k += 1
                root = {"type": "column", "children": [{"type": "chip", "label": "{{clock.time}}"}] * k}
                (self.dir / f"{c}-{n}.json").write_text(json.dumps({"version": 1, "name": "t", "root": root}))

    def messages(self):
        return [m for _, _, m in wc.template_problems(self.dir)]

    def test_a_complete_distinct_set_passes(self):
        self.write_all()
        self.assertEqual(self.messages(), [])

    def test_missing_extra_duplicate_and_unbound_templates_are_reported(self):
        self.write_all()
        (self.dir / "sports-5.json").unlink()
        (self.dir / "golf-1.json").write_text("{}")
        same = json.loads((self.dir / "weather-1.json").read_text())
        (self.dir / "weather-2.json").write_text(json.dumps(same))
        plain = json.loads((self.dir / "finance-1.json").read_text())
        for child in plain["root"]["children"]:
            child["label"] = "static"
        (self.dir / "finance-1.json").write_text(json.dumps(plain))
        msgs = self.messages()
        for needle in ("missing sports-5.json", "golf-1.json is not a template name",
                       "same structure as weather-1.json", "uses no binding"):
            self.assertTrue(any(needle in m for m in msgs), f"{needle!r} not in {msgs}")


try:
    import jsonschema  # optional cross-check only; never a dependency
except ImportError:
    jsonschema = None


@unittest.skipUnless(jsonschema, "jsonschema not installed; cross-check against a reference validator SKIPPED")
class AgreesWithJsonschema(unittest.TestCase):
    def test_same_verdicts_on_a_spread_of_widgets(self):
        s = skeleton_spec()
        samples = [{"version": 1, "name": "a", "root": {"type": t}} for t in wc.NODE_TYPES] + [
            {"version": 1, "name": "a", "root": {"type": "card", "tone": "primary_container"}},
            {"version": 1, "name": "a", "root": {"type": "card", "tone": "blue"}},
            {"version": 2, "name": "a", "root": {"type": "row"}},
            {"version": 1, "root": {"type": "row"}},
            {"version": 1, "name": "a", "root": {"type": "row", "extra": 1}},
            {"version": 1, "name": "a", "root": {"type": "nope"}},
        ]
        ref = jsonschema.Draft202012Validator(s)
        for w in samples:
            self.assertEqual(not wc.validate(w, s, s), ref.is_valid(w), w)


if __name__ == "__main__":
    unittest.main()
