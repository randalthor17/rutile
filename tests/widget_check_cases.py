"""Widgets and what tools/widget_check.py finds in them, for the shell's port (WidgetCheck.js, D85): qtws.py writes
them to the qml tests' data, and tst_widget_check.qml checks that the JavaScript finds the same."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import widget_check as wc  # noqa: E402

SCHEMA = json.loads(wc.SCHEMA.read_text())
CHIP = {"type": "chip", "label": "x"}


def w(root, **extra):
    return dict({"version": 1, "name": "T", "root": root}, **extra)


BROKEN = {
    "unknown field": w({"type": "chip", "label": "x", "colour": "red"}),
    "content color as tone": w({"type": "card", "tone": "on_primary", "children": [CHIP]}),
    "progress above 1": w({"type": "progress", "value": 1.5}),
    "code in a binding": w({"type": "progress", "value": "{{countdown.left}} + 1"}),
    "empty children": w({"type": "column", "children": []}),
    "grid without columns": w({"type": "grid", "children": [CHIP]}),
    "grid of 9 columns": w({"type": "grid", "columns": 9, "children": [CHIP]}),
    "unknown node type": w({"type": "slider"}),
    "no type": w({"label": "x"}),
    "aspect not w:h": w({"type": "heroImage", "source": "a.png", "aspect": "wide"}),
    "icon not a ligature name": w({"type": "header", "title": "x", "icon": "Bad Icon"}),
    "deep unknown field": w({"type": "column", "children": [{"type": "row", "children": [{"type": "stat", "value": "1", "x": 1}]}]}),
    "unknown source": w({"type": "chip", "label": "{{todo.title}}"}),
    "unknown field of a source": w({"type": "chip", "label": "{{battery.volts}}"}),
    "below a number": w({"type": "chip", "label": "{{battery.level.x}}"}),
    "a list's item field": w({"type": "listRow", "title": "{{calendar.events.nope}}"}, sources={"calendar": {"path": "~/c"}}),
    "a document itself": w({"type": "chip", "label": "{{files.json}}"}, sources={"files": {"path": "~/f"}}),
    "missing options": w({"type": "chip", "label": "{{countdown.text}}"}),
    "bad option": w({"type": "chip", "label": "{{countdown.text}}"}, sources={"countdown": {"target": "soon"}}),
    "http every too often": w({"type": "chip", "label": "{{http.a}}"}, sources={"http": {"url": "https://x.org/", "every": 5}}),
    "unknown source option": w({"type": "chip", "label": "x"}, sources={"weather": {"city": "Berlin"}}),
    "wrong version": dict(w(CHIP), version=2),
    "no name, no root": {"version": 1},
    "name too long": dict(w(CHIP), name="n" * 61),
    "unicode label too long": w({"type": "chip", "label": "°" * 201}),
    "emoji name within the limit": dict(w(CHIP), name="\U0001F600" * 31),   # 31 characters, 62 UTF-16 units
    "not an object": [1, 2],
    "a number for a label": w({"type": "chip", "label": 5}),
    "constructor as a field": w({"type": "chip", "label": "x", "constructor": 1}),
    "gauge without a value": w({"type": "chart", "kind": "gauge"}),
    "pie without series": w({"type": "chart", "kind": "pie", "values": [1, 2]}),
    "bar with neither": w({"type": "chart", "kind": "bar"}),
    "unknown chart kind": w({"type": "chart", "kind": "radar", "values": [1]}),
    "series item without a label": w({"type": "chart", "kind": "donut", "series": [{"value": 1}]}),
    "values as code": w({"type": "chart", "kind": "line", "values": "{{system.cpuHistory}} * 2"}),
    "values field unknown": w({"type": "chart", "kind": "line", "values": "{{system.cpuHist}}"}),
    "gpu card option": w({"type": "chip", "label": "{{gpu.usage}}"}, sources={"gpu": {"card": "/dev/dri/card1"}}),
    "two lines": w({"type": "chart", "kind": "line", "series": [{"label": "Down", "value": "{{system.downloadHistory}}"},
                                                              {"label": "Up", "value": "{{system.uploadHistory}}"}]}),
    "a line with neither": w({"type": "chart", "kind": "line"}),
    "a good chart": w({"type": "chart", "kind": "bar", "series": [{"label": "A", "value": "{{gpu.power}}", "tone": "tertiary"}]}),
    "many problems": w({"type": "column", "children": [{"type": "chip", "x%d" % i: 1} for i in range(20)]}),
}


def problems(widget):
    found = wc.validate(widget, SCHEMA, SCHEMA) + wc.binding_problems(widget)
    out = [{"path": wc.path_str(p), "message": m} for p, m in found[:wc.MAX_PER_FILE]]
    if len(found) > wc.MAX_PER_FILE:
        out.append({"path": "$", "message": f"... and {len(found) - wc.MAX_PER_FILE} more; fix these first"})
    return out


def cases():
    out = [{"name": name, "widget": widget, "problems": problems(widget)} for name, widget in BROKEN.items()]
    for folder in ("examples", "templates"):
        for f in sorted((ROOT / "widgets" / folder).glob("*.json")):
            widget = json.loads(f.read_text())
            out.append({"name": f"{folder}/{f.name}", "widget": widget, "problems": problems(widget)})
    return out


if __name__ == "__main__":
    json.dump(cases(), sys.stdout, ensure_ascii=False, indent=1)
