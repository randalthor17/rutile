#!/usr/bin/env python3
"""Check Rutile widgets: the schema against the spec's rules, and widget files against the schema.

    widget_check.py                 check widgets/spec.schema.json, then every widgets/examples/*.json
                                    and widgets/templates/*.json against it
    widget_check.py FILE ...        check only these widget files (against widgets/spec.schema.json)
    widget_check.py --schema S ...  use another schema file

Standard library only, so the local model can run it in any shell (it once spent dozens of tool calls
trying to install `jsonschema`). It implements the subset of JSON Schema 2020-12 a widget spec needs and
REJECTS any other keyword, so a schema can never rely on a rule nothing checks. Output is one line per
problem, `file: $.json.path: message`, capped per file so a broken file cannot flood a model's context.
Exit status: 0 all good, 1 problems found, 2 usage error. A first piece of plan item 4.6.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "widgets" / "spec.schema.json"
ROLES = ROOT / "theme" / "roles.json"
DRAFT = "https://json-schema.org/draft/2020-12/schema"
MAX_PER_FILE = 15

# The spec's node types and data sources (docs/sidework/tasks/widget-schema.md, plan item 4.1).
NODE_TYPES = ["row", "column", "grid", "card", "header", "tile", "heroImage", "stat", "progress", "listRow", "chip"]
SOURCES = ["clock", "weather", "calendar", "battery", "system", "countdown", "http", "files"]
BINDING = re.compile(r"\{\{\s*([^{}]*?)\s*\}\}")
BINDING_OK = re.compile(r"^(%s)\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$" % "|".join(SOURCES))

ANNOTATIONS = {"$schema", "$id", "$comment", "title", "description", "examples", "default", "deprecated"}
SUPPORTED = ANNOTATIONS | {
    "$defs", "$ref", "type", "enum", "const", "properties", "required", "additionalProperties", "items",
    "minItems", "maxItems", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minLength",
    "maxLength", "pattern", "oneOf", "anyOf", "allOf", "not", "if", "then", "else",
}
TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
}


class SchemaError(Exception):
    """The schema itself is unusable (bad $ref, unsupported keyword, wrong shape)."""


def path_str(path):
    out = "$"
    for p in path:
        out += f"[{p}]" if isinstance(p, int) else f".{p}"
    return out


def short(value):
    text = json.dumps(value)
    return text if len(text) <= 60 else text[:57] + "..."


def resolve(root, ref):
    if not ref.startswith("#/"):
        raise SchemaError(f"$ref {ref!r}: only local refs like #/$defs/name are supported")
    node = root
    for part in ref[2:].split("/"):
        part = part.replace("~1", "/").replace("~0", "~")
        if not isinstance(node, dict) or part not in node:
            raise SchemaError(f"$ref {ref!r} does not resolve")
        node = node[part]
    return node


def check_keywords(schema, where="$"):
    """Raise SchemaError for keywords this validator does not implement."""
    if isinstance(schema, bool):
        return
    if not isinstance(schema, dict):
        raise SchemaError(f"{where}: a schema must be an object or a boolean")
    unknown = sorted(set(schema) - SUPPORTED)
    if unknown:
        raise SchemaError(f"{where}: unsupported keyword(s) {', '.join(unknown)}; "
                          f"use only: {', '.join(sorted(SUPPORTED - ANNOTATIONS))}")
    for key in ("properties", "$defs"):
        for name, sub in schema.get(key, {}).items():
            check_keywords(sub, f"{where}.{key}.{name}")
    for key in ("items", "not", "if", "then", "else"):
        if key in schema:
            check_keywords(schema[key], f"{where}.{key}")
    if isinstance(schema.get("additionalProperties"), dict):
        check_keywords(schema["additionalProperties"], f"{where}.additionalProperties")
    for key in ("oneOf", "anyOf", "allOf"):
        for i, sub in enumerate(schema.get(key, [])):
            check_keywords(sub, f"{where}.{key}[{i}]")


def validate(value, schema, root, path=(), depth=0):
    """Problems as (path, message) pairs; empty when `value` matches `schema`."""
    if depth > 64:
        return [(path, "nesting too deep (a $ref loop?)")]
    if schema is True:
        return []
    if schema is False:
        return [(path, "no value is allowed here")]
    errs = []
    if "$ref" in schema:
        errs += validate(value, resolve(root, schema["$ref"]), root, path, depth + 1)
    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(TYPES[t](value) for t in types):
            return errs + [(path, f"expected {' or '.join(types)}, got {short(value)}")]
    if "const" in schema and value != schema["const"]:
        errs.append((path, f"must be {short(schema['const'])}, got {short(value)}"))
    if "enum" in schema and value not in schema["enum"]:
        allowed = ", ".join(map(short, schema["enum"][:12])) + (", ..." if len(schema["enum"]) > 12 else "")
        errs.append((path, f"{short(value)} is not one of: {allowed}"))
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errs.append((path, f"shorter than {schema['minLength']} characters"))
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errs.append((path, f"longer than {schema['maxLength']} characters"))
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errs.append((path, f"{short(value)} does not match pattern {schema['pattern']}"))
    if TYPES["number"](value):
        for key, bad in (("minimum", lambda v, b: v < b), ("maximum", lambda v, b: v > b),
                         ("exclusiveMinimum", lambda v, b: v <= b), ("exclusiveMaximum", lambda v, b: v >= b)):
            if key in schema and bad(value, schema[key]):
                errs.append((path, f"{value} violates {key} {schema[key]}"))
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errs.append((path, f"needs at least {schema['minItems']} item(s)"))
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errs.append((path, f"allows at most {schema['maxItems']} item(s)"))
        if "items" in schema:
            for i, item in enumerate(value):
                errs += validate(item, schema["items"], root, path + (i,), depth + 1)
    if isinstance(value, dict):
        props = schema.get("properties", {})
        for name in schema.get("required", []):
            if name not in value:
                errs.append((path, f"missing required field {name!r}"))
        extra = schema.get("additionalProperties", True)
        for name, item in value.items():
            if name in props:
                errs += validate(item, props[name], root, path + (name,), depth + 1)
            elif extra is False:
                allowed = ", ".join(sorted(props)) or "none"
                errs.append((path, f"unknown field {name!r} (allowed here: {allowed})"))
            elif isinstance(extra, dict):
                errs += validate(item, extra, root, path + (name,), depth + 1)
    for sub in schema.get("allOf", []):
        errs += validate(value, sub, root, path, depth + 1)
    if "anyOf" in schema:
        results = [validate(value, sub, root, path, depth + 1) for sub in schema["anyOf"]]
        if all(results):
            errs += min(results, key=len)
    if "oneOf" in schema:
        results = [validate(value, sub, root, path, depth + 1) for sub in schema["oneOf"]]
        passing = sum(1 for r in results if not r)
        if passing == 0:
            errs += explain_oneof(value, schema["oneOf"], results, root, path)
        elif passing > 1:
            errs.append((path, f"matches {passing} of the oneOf branches; make them mutually exclusive"))
    if "not" in schema and not validate(value, schema["not"], root, path, depth + 1):
        errs.append((path, "matches a schema it must not match"))
    if "if" in schema:
        branch = "then" if not validate(value, schema["if"], root, path, depth + 1) else "else"
        if branch in schema:
            errs += validate(value, schema[branch], root, path, depth + 1)
    return errs


def explain_oneof(value, branches, results, root, path):
    """For a node with a `type`, report the errors of the branch for that type, not of every branch."""
    if isinstance(value, dict) and "type" in value:
        for sub, res in zip(branches, results):
            target = resolve(root, sub["$ref"]) if "$ref" in sub else sub
            if target.get("properties", {}).get("type", {}).get("const") == value["type"]:
                return res
        return [(path, f"no node type {short(value['type'])}; known: {', '.join(NODE_TYPES)}")]
    return min(results, key=len)


def strings(value, path=()):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, list):
        for i, item in enumerate(value):
            yield from strings(item, path + (i,))
    elif isinstance(value, dict):
        for k, item in value.items():
            yield from strings(item, path + (k,))


def binding_problems(widget):
    errs = []
    for path, text in strings(widget):
        for m in BINDING.finditer(text):
            if not BINDING_OK.match(m.group(1)):
                errs.append((path, f"binding {m.group(0)!r} must be {{{{source.field}}}} with a source from: "
                                   f"{', '.join(SOURCES)} (no code, no spaces)"))
    return errs


def node_schemas(schema):
    """Every subschema that defines one node type, keyed by that type (a `type` const in properties)."""
    found = {}

    def walk(s):
        if isinstance(s, dict):
            const = s.get("properties", {}).get("type", {}).get("const") if isinstance(s.get("properties"), dict) else None
            if isinstance(const, str):
                found.setdefault(const, []).append(s)
            for v in s.values():
                walk(v)
        elif isinstance(s, list):
            for v in s:
                walk(v)
    walk(schema)
    return found


def spec_rule_problems(schema, roles):
    """The rules from the widget-schema brief that are about the schema itself."""
    errs = []
    if schema.get("$schema") != DRAFT:
        errs.append((("$schema",), f"must be {DRAFT!r}"))
    nodes = node_schemas(schema)
    for t in NODE_TYPES:
        if t not in nodes:
            errs.append(((), f"no subschema for node type {t!r} (one with \"properties\": {{\"type\": {{\"const\": \"{t}\"}}}})"))
    for t in sorted(set(nodes) - set(NODE_TYPES)):
        errs.append(((), f"node type {t!r} is not in the spec ({', '.join(NODE_TYPES)})"))
    for t, subs in nodes.items():
        for s in subs:
            if s.get("additionalProperties") is not False:
                errs.append(((), f"node {t!r}: needs \"additionalProperties\": false so unknown fields are rejected"))
    for path, tone in find_property(schema, "tone"):
        target = resolve(schema, tone["$ref"]) if isinstance(tone, dict) and "$ref" in tone else tone
        enum = target.get("enum") if isinstance(target, dict) else None
        if not enum:
            errs.append((path, "tone must be restricted with an enum of role names from theme/roles.json"))
        else:
            bad = [r for r in enum if r not in roles]
            if bad:
                errs.append((path, f"tone enum has names that are not in theme/roles.json: {', '.join(map(str, bad))}"))
    return errs


def find_property(schema, name, path=()):
    if isinstance(schema, dict):
        if isinstance(schema.get("properties"), dict) and name in schema["properties"]:
            yield path + ("properties", name), schema["properties"][name]
        for k, v in schema.items():
            yield from find_property(v, name, path + (k,))
    elif isinstance(schema, list):
        for i, v in enumerate(schema):
            yield from find_property(v, name, path + (i,))


def load_json(path):
    try:
        return json.loads(Path(path).read_text()), None
    except FileNotFoundError:
        return None, "file not found"
    except json.JSONDecodeError as e:
        return None, f"not valid JSON: {e.msg} at line {e.lineno} column {e.colno}"


def report(name, problems, out):
    for path, msg in problems[:MAX_PER_FILE]:
        print(f"{name}: {path_str(path)}: {msg}", file=out)
    if len(problems) > MAX_PER_FILE:
        print(f"{name}: ... and {len(problems) - MAX_PER_FILE} more; fix these first", file=out)


def check_widget(path, schema, out):
    widget, err = load_json(path)
    if err:
        report(path, [((), err)], out)
        return False
    problems = validate(widget, schema, schema) + binding_problems(widget)
    report(path, problems, out)
    return not problems


def rel(p):
    try:
        return str(Path(p).resolve().relative_to(ROOT))
    except ValueError:
        return str(p)


def main(argv, out=sys.stdout):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--schema", default=str(SCHEMA))
    args = ap.parse_args(argv)
    schema_name = rel(args.schema)
    schema, err = load_json(args.schema)
    if err:
        report(schema_name, [((), err)], out)
        return 1
    try:
        check_keywords(schema)
    except SchemaError as e:
        report(schema_name, [((), str(e))], out)
        return 1
    ok = True
    if not args.files:
        roles = json.loads(ROLES.read_text())["roles"]
        problems = spec_rule_problems(schema, roles)
        report(schema_name, problems, out)
        ok = not problems
        files = sorted((ROOT / "widgets" / "examples").glob("*.json")) + sorted((ROOT / "widgets" / "templates").glob("*.json"))
        if not files:
            print("widgets/examples: no widget files to check", file=out)
            ok = False
    else:
        files = [Path(f) for f in args.files]
    try:
        for f in files:
            ok = check_widget(rel(f), schema, out) and ok
    except SchemaError as e:
        report(schema_name, [((), str(e))], out)
        return 1
    print(("ok: " if ok else "FAILED: ") + f"{schema_name} and {len(files)} widget file(s)", file=out)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
