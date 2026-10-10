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


def qml_import_dirs(tool):
    """Directories holding Qt's QML modules (QtQuick.Window, QtTest, ...).

    Some installs (notably nix shells) leave them off the tool's default import
    path, so derive them from where the tool really lives. RUTILE_QML_IMPORT
    (os.pathsep separated) is added first and always wins.
    """
    dirs = [d for d in os.environ.get("RUTILE_QML_IMPORT", "").split(os.pathsep) if d]
    prefix = Path(os.path.realpath(tool)).parent.parent
    for rel in ("lib/qt-6/qml", "lib/qt6/qml", "lib/qml", "qml"):
        d = prefix / rel
        if (d / "QtQuick").is_dir():
            dirs.append(str(d))
    seen, out = set(), []
    for d in dirs:
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out


def qml_env(dirs, base):
    """Copy of base env with dirs merged (first) into QML_IMPORT_PATH and QML2_IMPORT_PATH.

    Existing values of either variable are kept, so a devshell's own setup is never lost.
    """
    parts = list(dirs)
    for var in ("QML_IMPORT_PATH", "QML2_IMPORT_PATH"):
        parts += [p for p in base.get(var, "").split(os.pathsep) if p]
    seen, merged = set(), []
    for p in parts:
        if p not in seen:
            seen.add(p)
            merged.append(p)
    env = dict(base)
    if merged:
        env["QML_IMPORT_PATH"] = env["QML2_IMPORT_PATH"] = os.pathsep.join(merged)
    return env


def hint(output):
    """Extra advice appended to Qt failures that are environment problems, not test failures."""
    if "is not installed" in output or "Type TestCase unavailable" in output:
        return ("\nHINT: Qt's QML modules were not found on the import path. Point RUTILE_QML_IMPORT at the "
                "directory containing QtQuick/ and QtTest/ (nixpkgs: <qtdeclarative>/lib/qt-6/qml), e.g.\n"
                "  RUTILE_QML_IMPORT=$(dirname $(dirname $(readlink -f $(which qmltestrunner))))/lib/qt-6/qml make check")
    return ""


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
    # Fonts are not vendored. When the real files are found (RUTILE_FONT_DIRS) an extra QML
    # test loads them into Qt; otherwise that test is simply not part of the run.
    import otinfo
    fonts = json.loads((ROOT / "theme" / "fonts.json").read_text())
    found = {}
    for kind in ("text", "icons"):
        path = otinfo.find_font(fonts[kind]["file"], otinfo.font_dirs())
        if path:
            found[kind] = path
    (data / "fontpaths.json").write_text(json.dumps(found))
    if found:
        shutil.copy(ROOT / "tests" / "qml_optional" / "tst_fonts.qml", tests / "tst_fonts.qml")
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
        dirs = qml_import_dirs(runner)
        env = qml_env(dirs, dict(os.environ, QT_QPA_PLATFORM="offscreen", QML_XHR_ALLOW_FILE_READ="1"))
        cmd = [runner, "-input", str(ws / "tests")]
        for d in dirs:
            cmd += ["-import", d]
        proc = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=300)
        out = proc.stdout + proc.stderr
        if proc.returncode != 0:
            out += hint(out)
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
        incs = ["-I", str(ws)]
        for d in qml_import_dirs(linter):
            incs += ["-I", d]
        proc = subprocess.run([linter, *incs, *files], capture_output=True, text=True,
                              env=qml_env(qml_import_dirs(linter), dict(os.environ)))
        out = (proc.stdout + proc.stderr).replace(str(ws) + "/", "")
        return proc.returncode, out + (hint(out) if proc.returncode else "")
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
