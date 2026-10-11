#!/usr/bin/env python3
"""Hermetic Qt workspace for linting and running the QML tests offscreen.

Quickshell (not Qt alone) provides FileView/Scope, so files importing it are
left out of the workspace; singletons get a generated qmldir because Quickshell
normally registers them itself.

    qtws.py lint     qmllint the QML that can be checked without Quickshell
    qtws.py test     run tests/qml/tst_*.qml with qmltestrunner
    qtws.py render [--mode dark|light] [--out DIR]
                     render the gallery offscreen to a PNG (to look at the result)

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
MODULES = ("common", "components", "gallery")


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


def summarize(output):
    """The failing lines of qmltestrunner output (each FAIL! plus its Loc/Actual/Expected), so a long
    run's real error is the first thing shown instead of being cut off by truncation."""
    lines = output.splitlines()
    out = []
    for i, line in enumerate(lines):
        if line.startswith("FAIL!"):
            out.append(line)
            for nxt in lines[i + 1:i + 4]:
                if nxt.lstrip().startswith(("Loc:", "Actual", "Expected")):
                    out.append(nxt)
    return "\n".join(out)


def hint(output):
    """Extra advice appended to Qt failures that are environment problems, not test failures."""
    # Only when a Qt module itself is missing; a missing qs.* module is a different problem.
    if re.search(r'module "Qt[\w.]*" is not installed', output) or "Type TestCase unavailable" in output:
        return ("\nHINT: Qt's QML modules were not found on the import path. Point RUTILE_QML_IMPORT at the "
                "directory containing QtQuick/ and QtTest/ (nixpkgs: <qtdeclarative>/lib/qt-6/qml), e.g.\n"
                "  RUTILE_QML_IMPORT=$(dirname $(dirname $(readlink -f $(which qmltestrunner))))/lib/qt-6/qml make check")
    return ""


def workspace():
    """Return a temp dir laid out like Quickshell's import root.

    qs/common and qs/components hold copies of shell/common and shell/components with
    generated qmldir files, so tests and lint use `import qs.common` exactly as the shell
    does (Quickshell registers singletons itself; plain Qt needs a qmldir). tests/ and
    data/ sit beside qs/. Files importing Quickshell are left out.
    """
    ws = Path(tempfile.mkdtemp(prefix="rutile-qtws-"))
    tests, data = ws / "tests", ws / "data"
    for d in (tests, data):
        d.mkdir()
    for module in MODULES:
        src = ROOT / "shell" / module
        dst = ws / "qs" / module
        dst.mkdir(parents=True)
        entries = [f"module qs.{module}"]
        for f in sorted(src.iterdir()) if src.is_dir() else []:
            text = f.read_text()
            if "import Quickshell" in text:
                continue
            shutil.copy(f, dst / f.name)
            if f.suffix == ".qml":
                kind = "singleton " if re.search(r"^pragma Singleton", text, re.M) else ""
                entries.append(f"{kind}{f.stem} {f.name}")
        (dst / "qmldir").write_text("\n".join(entries) + "\n")
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
        dirs = [str(ws)] + qml_import_dirs(runner)
        env = qml_env(dirs, dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                                 QML_XHR_ALLOW_FILE_READ="1"))
        cmd = [runner, "-input", str(ws / "tests")]
        for d in dirs:
            cmd += ["-import", d]
        proc = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=300)
        out = proc.stdout + proc.stderr
        if proc.returncode != 0:
            out = (summarize(out) + "\n\n" if summarize(out) else "") + out + hint(out)
        m = re.search(r"Totals: (\d+) passed, (\d+) failed, (\d+) skipped", out)
        counts = tuple(map(int, m.groups())) if m else None
        return proc.returncode, out, counts
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def render_gallery(out_dir, mode="dark", width=1180):
    """Render shell/gallery/GalleryContent offscreen as scrolled slices out_dir/gallery-<mode>-N.png.

    Uses the real fonts when RUTILE_FONT_DIRS finds them. Returns (exit code, output, list of slice PNGs).
    """
    runner = qt_tool("qmltestrunner")
    if not runner:
        return SKIPPED, "qmltestrunner not found (set RUTILE_QT_BIN)", None
    ws = workspace()
    try:
        for f in (ws / "tests").glob("*.qml"):
            f.unlink()
        shutil.copy(ROOT / "tests" / "qml_render" / "tst_render.qml", ws / "tests" / "tst_render.qml")
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        png = out_dir / f"gallery-{mode}.png"
        for old in out_dir.glob(f"gallery-{mode}-*.png"):
            old.unlink()
        (ws / "data" / "render.json").write_text(json.dumps({"out": str(png), "mode": mode, "width": width}))
        dirs = [str(ws)] + qml_import_dirs(runner)
        env = qml_env(dirs, dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                                 QML_XHR_ALLOW_FILE_READ="1"))
        cmd = [runner, "-input", str(ws / "tests")]
        for d in dirs:
            cmd += ["-import", d]
        proc = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=300)
        out = proc.stdout + proc.stderr
        slices = sorted(out_dir.glob(f"gallery-{mode}-*.png"), key=lambda q: int(q.stem.rsplit('-', 1)[1]))
        return proc.returncode, out, (slices if slices else None)
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def run_lint():
    linter = qt_tool("qmllint")
    if not linter:
        return SKIPPED, "qmllint not found (set RUTILE_QT_BIN)"
    ws = workspace()
    try:
        files = sorted(str(p) for m in MODULES for p in (ws / "qs" / m).glob("*.qml"))
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
    if argv and argv[0] == "render":
        mode = argv[argv.index("--mode") + 1] if "--mode" in argv else "dark"
        out_dir = argv[argv.index("--out") + 1] if "--out" in argv else "render"
        code, out, png = render_gallery(out_dir, mode)
        if code == SKIPPED:
            print(f"render: SKIPPED, {out}")
            return 0
        print("\n".join(map(str, png)) if png else out[-2000:])
        return 0 if png else 1
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
