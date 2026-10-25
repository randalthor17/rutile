#!/usr/bin/env python3
"""Check docs/llm/TOKENS.md and COMPONENTS.md against the QML source (the llm-docs task's acceptance).

    llm_docs_check.py          check both documents; one line per problem, exit 1 if any

Standard library only. What it checks, from docs/sidework/tasks/llm-docs.md:
  - TOKENS.md has a section per singleton (a heading naming it) listing every property of that singleton
    by exact name in backticks, and states the `on_primary` -> `Colors.primaryOn` rule;
  - COMPONENTS.md has a section per component listing every public property and signal in backticks;
  - every ```qml example only uses `Singleton.member` names that exist, only components that exist, and
    contains no hex colors and no numeric radius or duration.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMMON = ROOT / "shell" / "common"
COMPONENTS = ROOT / "shell" / "components"
DOCS = ROOT / "docs" / "llm"
SINGLETONS = ["Colors", "Shapes", "Elevation", "Motion", "Type", "Fonts", "Spacing"]
MAX_PROBLEMS = 25

# Direct children of the root object only: four spaces of indentation.
MEMBER = re.compile(r"^    (?:readonly\s+)?property\s+[\w<>.]+\s+(\w+)|^    signal\s+(\w+)|^    function\s+(\w+)", re.M)
PUBLIC = re.compile(r"^    property\s+[\w<>.]+\s+(\w+)|^    signal\s+(\w+)", re.M)
HEADING = re.compile(r"^#{1,6}\s+(.*)$", re.M)
QML_BLOCK = re.compile(r"```qml\n(.*?)```", re.S)


def members(path, pattern=MEMBER):
    return [next(g for g in m.groups() if g) for m in pattern.finditer(path.read_text())]


def components():
    return sorted(p.stem for p in COMPONENTS.glob("*.qml"))


def sections(text):
    """{heading text: body} for every heading."""
    heads = list(HEADING.finditer(text))
    return {h.group(1).strip(): text[h.end():heads[i + 1].start() if i + 1 < len(heads) else len(text)]
            for i, h in enumerate(heads)}


def section_for(name, secs):
    for head, body in secs.items():
        if re.search(rf"\b{re.escape(name)}\b", head):
            return body
    return None


def listed(names, body):
    return [n for n in names if f"`{n}`" not in body and not re.search(rf"`[^`\n]*\b{re.escape(n)}\b[^`\n]*`", body)]


def check_examples(doc, text, known, comps):
    errs = []
    for i, block in enumerate(QML_BLOCK.findall(text), start=1):
        where = f"{doc}: qml example {i}"
        for hexcol in re.findall(r"#[0-9a-fA-F]{3,8}\b", block):
            errs.append(f"{where}: hardcoded color {hexcol}; use a Colors role")
        for key in ("radius", "duration"):
            for m in re.finditer(rf"\b{key}\s*:\s*-?\d", block):
                errs.append(f"{where}: numeric {key} ({block[m.start():m.end() + 6].split()[0:2]}); use Shapes / Motion")
        for single, member in re.findall(r"\b(%s)\.(\w+)" % "|".join(SINGLETONS), block):
            if member not in known[single]:
                errs.append(f"{where}: {single}.{member} does not exist")
        for comp in re.findall(r"^\s*([A-Z]\w*)\s*\{", block, re.M):
            if comp not in comps and comp not in QT_TYPES:
                errs.append(f"{where}: unknown component {comp}")
    return errs


# Plain Qt Quick types an example may reasonably use alongside ours.
QT_TYPES = {"Item", "Rectangle", "Text", "Row", "Column", "RowLayout", "ColumnLayout", "Grid", "Repeater",
            "MouseArea", "Behavior", "NumberAnimation", "ColorAnimation", "Component", "Loader", "QtObject"}


def main(argv, out=sys.stdout):
    errs = []
    known = {s: members(COMMON / f"{s}.qml") for s in SINGLETONS}
    comps = components()
    tokens, comp_doc = DOCS / "TOKENS.md", DOCS / "COMPONENTS.md"
    if not tokens.exists():
        errs.append("docs/llm/TOKENS.md: file not found")
    else:
        text = tokens.read_text()
        secs = sections(text)
        for s in SINGLETONS:
            body = section_for(s, secs)
            if body is None:
                errs.append(f"docs/llm/TOKENS.md: no section (heading) for {s}")
                continue
            missing = listed(known[s], body)
            if missing:
                errs.append(f"docs/llm/TOKENS.md: {s} section lacks {len(missing)} member(s): "
                            + ", ".join(missing[:12]) + (", ..." if len(missing) > 12 else ""))
        if "primaryOn" not in text:
            errs.append("docs/llm/TOKENS.md: must state that on_primary is written Colors.primaryOn, and why")
        if len(QML_BLOCK.findall(text)) < 6:
            errs.append("docs/llm/TOKENS.md: needs at least 6 ```qml examples")
        errs += check_examples("docs/llm/TOKENS.md", text, known, comps)
    if not comp_doc.exists():
        errs.append("docs/llm/COMPONENTS.md: file not found")
    else:
        text = comp_doc.read_text()
        secs = sections(text)
        for c in comps:
            body = section_for(c, secs)
            if body is None:
                errs.append(f"docs/llm/COMPONENTS.md: no section (heading) for {c}")
                continue
            missing = listed(members(COMPONENTS / f"{c}.qml", PUBLIC), body)
            if missing:
                errs.append(f"docs/llm/COMPONENTS.md: {c} section lacks: " + ", ".join(missing))
        errs += check_examples("docs/llm/COMPONENTS.md", text, known, comps)
    for e in errs[:MAX_PROBLEMS]:
        print(e, file=out)
    if len(errs) > MAX_PROBLEMS:
        print(f"... and {len(errs) - MAX_PROBLEMS} more; fix these first", file=out)
    print("ok: docs/llm" if not errs else f"FAILED: {len(errs)} problem(s) in docs/llm", file=out)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
