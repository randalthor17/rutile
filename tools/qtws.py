#!/usr/bin/env python3
"""Hermetic Qt workspace for linting and running the QML tests offscreen.

Quickshell (not Qt alone) provides FileView/Scope, so files importing it are
left out of the workspace; singletons get a generated qmldir because Quickshell
normally registers them itself.

    qtws.py lint     qmllint the QML that can be checked without Quickshell
    qtws.py test     run tests/qml/tst_*.qml with qmltestrunner

Exit code 3 means Qt tools were not found (callers treat that as "skipped").
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIPPED = 3


def qt_tool(name):
    """Find a Qt tool. If RUTILE_QT_BIN is set it is the only place searched."""
    override = os.environ.get("RUTILE_QT_BIN")
    if override is not None:
        p = Path(override) / name
        return str(p) if p.exists() else None
    if (Path("/usr/lib/qt6/bin") / name).exists():
        return str(Path("/usr/lib/qt6/bin") / name)
    for cand in (name, name + "6"):
        found = shutil.which(cand)
        if found:
            return found
    return None


def workspace():
    """Return a temp dir with imp/ (shell/common + qmldir), tests/, data/."""
    ws = Path(tempfile.mkdtemp(prefix="rutile-qtws-"))
    imp, tests, data = ws / "imp", ws / "tests", ws / "data"
    for d in (imp, tests, data):
        d.mkdir()
    entries = []
    for f in sorted((ROOT / "shell" / "common").iterdir()):
        text = f.read_text()
        if "import Quickshell" in text:
            continue
        shutil.copy(f, imp / f.name)
        if f.suffix == ".qml":
            kind = "singleton " if re.search(r"^pragma Singleton", text, re.M) else ""
            entries.append(f"{kind}{f.stem} {f.name}")
    (imp / "qmldir").write_text("\n".join(entries) + "\n")
    for f in (ROOT / "tests" / "qml").glob("*.qml"):
        shutil.copy(f, tests / f.name)
    shutil.copy(ROOT / "theme" / "roles.json", data)
    shutil.copy(ROOT / "tokens" / "m3e.json", data)
    shutil.copy(ROOT / "theme" / "fixtures" / "palette-134aae-tonal-spot-dark.json", data / "palette.json")
    sys.path.insert(0, str(ROOT / "tests"))
    import spring_ref
    (data / "spring_cases.json").write_text(json.dumps(spring_ref.cases()))
    return ws


def run_tests(verbose=False):
    runner = qt_tool("qmltestrunner")
    if not runner:
        return SKIPPED, "qmltestrunner not found (set RUTILE_QT_BIN)", None
    ws = workspace()
    try:
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QML_XHR_ALLOW_FILE_READ="1")
        proc = subprocess.run([runner, "-input", str(ws / "tests")], capture_output=True, text=True,
                              env=env, timeout=300)
        out = proc.stdout + proc.stderr
        m = re.search(r"Totals: (\d+) passed, (\d+) failed, (\d+) skipped", out)
        counts = tuple(map(int, m.groups())) if m else None
        return proc.returncode, out, counts
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def run_lint():
    linter = qt_tool("qmllint")
    if not linter:
        return SKIPPED, "qmllint not found (set RUTILE_QT_BIN)"
    ws = workspace()
    try:
        files = sorted(str(p) for p in (ws / "imp").glob("*.qml"))
        proc = subprocess.run([linter, "-I", str(ws), *files], capture_output=True, text=True)
        return proc.returncode, (proc.stdout + proc.stderr).replace(str(ws) + "/", "")
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def main(argv):
    if not argv or argv[0] not in ("lint", "test"):
        print(__doc__)
        return 2
    if argv[0] == "lint":
        code, out = run_lint()
        if code == SKIPPED:
            print(f"qmllint: SKIPPED, {out}")
            return 0
        print(out.strip() or "qmllint: clean")
        return code
    code, out, counts = run_tests()
    if code == SKIPPED:
        print(f"qml tests: SKIPPED, {out}")
        return 0
    print(out if code else f"qml tests passed {counts}")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
