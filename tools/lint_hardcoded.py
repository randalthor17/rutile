#!/usr/bin/env python3
"""Fail on hardcoded colors, radii and durations in QML.

Design values must come from the token singletons (Colors, Shapes, Motion,
Type, ...). Append `// lint-ignore` to a line to allow a deliberate exception.

    lint_hardcoded.py [root]     root defaults to the repo root
"""
import re
import sys
from pathlib import Path

SCAN_DIRS = ("shell", "settings")
RULES = (
    ("hex color", re.compile(r"#[0-9a-fA-F]{3,8}\b")),
    ("numeric radius", re.compile(r"\bradius\s*:\s*\d")),
    ("numeric duration", re.compile(r"\bduration\s*:\s*\d")),
)


def scan(root):
    problems = []
    for d in SCAN_DIRS:
        for path in sorted((root / d).rglob("*.qml")) if (root / d).is_dir() else []:
            for no, line in enumerate(path.read_text().splitlines(), 1):
                if "lint-ignore" in line:
                    continue
                code = line.split("//", 1)[0]
                for label, rx in RULES:
                    if rx.search(code):
                        problems.append(f"{path.relative_to(root)}:{no}: {label}: {line.strip()}")
    return problems


def main(argv):
    root = Path(argv[0]) if argv else Path(__file__).resolve().parent.parent
    problems = scan(root)
    for p in problems:
        print(p, file=sys.stderr)
    if problems:
        print(f"{len(problems)} hardcoded design value(s); use tokens", file=sys.stderr)
        return 1
    print("lint: no hardcoded design values")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
