#!/usr/bin/env python3
"""Hermetic Qt workspace for linting and running the QML tests offscreen.

Quickshell (not Qt alone) provides FileView/Scope, so files importing it are
left out of the workspace; singletons get a generated qmldir because Quickshell
normally registers them itself.

    qtws.py lint     qmllint the QML that can be checked without Quickshell
    qtws.py test     run tests/qml/tst_*.qml with qmltestrunner
    qtws.py test-gpu run tests/qml_gpu through the real scene graph (needs a display session)
    qtws.py test-wayland [--screenshot FILE]
                     start the real shell (shell/shell.qml) under a headless sway, open Quick Settings over
                     IPC and check it loads cleanly; FILE gets a screenshot (needs grim)
    qtws.py test-qs  run tests/qs/tst_*.qml as shells under `quickshell`, offscreen (code that needs
                     Quickshell types, which qmltestrunner cannot load)
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
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Not a number: qmltestrunner exits with its failure count, so any int could be a real result.
SKIPPED = "skipped"
MODULES = ("common", "components", "gallery", "services", "quicksettings", "bar", "shelf", "launcher", "notifications")
# Files importing these need Quickshell at run time; qmltestrunner and qmllint skip them (test-qs covers them).
QUICKSHELL_IMPORTS = ("import Quickshell", "import qs.services")


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


def workspace(tests_dir="qml"):
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
            if any(i in text for i in QUICKSHELL_IMPORTS):
                continue
            shutil.copy(f, dst / f.name)
            if f.suffix == ".qml":
                kind = "singleton " if re.search(r"^pragma Singleton", text, re.M) else ""
                entries.append(f"{kind}{f.stem} {f.name}")
        (dst / "qmldir").write_text("\n".join(entries) + "\n")
    for f in (ROOT / "tests" / tests_dir).glob("*.qml"):
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
    if found and tests_dir == "qml":
        shutil.copy(ROOT / "tests" / "qml_optional" / "tst_fonts.qml", tests / "tst_fonts.qml")
    shutil.copy(ROOT / "theme" / "roles.json", data)
    shutil.copy(ROOT / "tokens" / "m3e.json", data)
    shutil.copy(ROOT / "theme" / "fixtures" / "palette-134aae-tonal-spot-dark.json", data / "palette.json")
    sys.path.insert(0, str(ROOT / "tests"))
    import spring_ref
    import shape_ref
    (data / "spring_cases.json").write_text(json.dumps(spring_ref.cases()))
    (data / "shape_cases.json").write_text(json.dumps(shape_ref.cases()))
    return ws


def has_display():
    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def run_tests(verbose=False, gpu=False):
    runner = qt_tool("qmltestrunner")
    if not runner:
        return SKIPPED, "qmltestrunner not found (set RUTILE_QT_BIN)", None
    if gpu and not has_display():
        return SKIPPED, "no display session (DISPLAY/WAYLAND_DISPLAY unset): GPU tests need a real one", None
    ws = workspace("qml_gpu" if gpu else "qml")
    try:
        dirs = [str(ws)] + qml_import_dirs(runner)
        if gpu:
            # the real scene graph: keep the session's platform and backend, only allow reading local files
            env = qml_env(dirs, dict(os.environ, QML_XHR_ALLOW_FILE_READ="1"))
        else:
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


def qs_workspace(test):
    """A shell directory for one tests/qs test: shell/ copied, the test as its shell.qml, QsTest.qml and
    the golden palette beside it."""
    ws = Path(tempfile.mkdtemp(prefix="rutile-qs-"))
    for d in MODULES:
        shutil.copytree(ROOT / "shell" / d, ws / d)
    shutil.copy(ROOT / "tests" / "qs" / "QsTest.qml", ws)
    shutil.copytree(ROOT / "tests" / "qs" / "bin", ws / "bin")
    shutil.copytree(ROOT / "tests" / "qs" / "apps", ws / "apps")
    shutil.copytree(ROOT / "tests" / "qs" / "config", ws / "config")
    shutil.copy(test, ws / "shell.qml")
    shutil.copy(ROOT / "theme" / "fixtures" / "palette-134aae-tonal-spot-dark.json", ws / "palette.json")
    return ws


def qs_test_env(test, ws):
    """Offscreen, never the session's compositor. `// env NAME=value` lines in the test add variables;
    @WS@ is the shell directory and @PATH@ the current PATH. No braces there: a `{` above the imports stops Quickshell resolving qs.*."""
    # never the session's compositor or niri
    env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "DISPLAY", "NIRI_SOCKET", "SWAYSOCK")}
    env["QT_QPA_PLATFORM"] = "offscreen"
    # never the user's settings or state (D45); a test's `// env XDG_CONFIG_HOME=@WS@/config/<name>` picks a fixture
    env["XDG_CONFIG_HOME"] = str(ws / "home" / "config")
    env["XDG_STATE_HOME"] = str(ws / "home" / "state")
    for name, value in re.findall(r"^// env (\w+)=(\S+)$", Path(test).read_text(), flags=re.M):
        env[name] = value.replace("@WS@", str(ws)).replace("@PATH@", os.environ.get("PATH", ""))
    return env


class PrivateBus:
    """A session D-Bus of the test's own, so the shell's notification server (plan 2.8) never meets the user's
    (or takes over theirs). Without dbus-daemon the address points nowhere: nothing reaches the session either."""

    def __enter__(self):
        exe = shutil.which("dbus-daemon")
        self.proc = None
        self.address = "unix:path=/nonexistent/rutile-no-bus"
        if exe:
            self.proc = subprocess.Popen([exe, "--session", "--nofork", "--print-address=1"],
                                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            self.address = self.proc.stdout.readline().strip() or self.address
        return self

    def __exit__(self, *exc):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def run_qs_tests(timeout=60):
    """(code, output, (passed, failed)); code is SKIPPED without the quickshell binary."""
    qs = shutil.which("quickshell")
    if not qs:
        return SKIPPED, "quickshell not found", None
    passed, failed, out = 0, 0, []
    for test in sorted((ROOT / "tests" / "qs").glob("tst_*.qml")):
        ws = qs_workspace(test)
        try:
            with PrivateBus() as bus:
                env = dict(qs_test_env(test, ws), DBUS_SESSION_BUS_ADDRESS=bus.address)
                r = subprocess.run([qs, "-p", str(ws / "shell.qml")], env=env,
                                   capture_output=True, text=True, timeout=timeout)
            text = r.stdout + r.stderr
        except subprocess.TimeoutExpired as e:
            text, r = f"timed out after {timeout} s\n{e.stdout or ''}", None
        finally:
            shutil.rmtree(ws, ignore_errors=True)
        done = re.search(r"QSTEST done checks=(\d+) failures=0", text)
        if r is not None and r.returncode == 0 and done and int(done.group(1)) > 0:
            passed += 1
        else:
            failed += 1
            lines = [l for l in text.splitlines() if "QSTEST" in l or "ERROR" in l or "WARN" in l]
            out.append(f"FAIL {test.name}:\n" + "\n".join(lines[-20:] or text.splitlines()[-20:]))
    return (1 if failed else 0), "\n".join(out), (passed, failed)


class HeadlessSway:
    """A headless sway with its own XDG_RUNTIME_DIR, so nothing reaches the session: no compositor, no
    PipeWire, no portal. The directory is short because Unix socket paths are capped at 108 bytes."""

    def __init__(self, width=1280, height=800):
        self.size = (width, height)

    def __enter__(self):
        uid_dir = Path(f"/run/user/{os.getuid()}")
        self.runtime = Path(tempfile.mkdtemp(prefix="rtl.", dir=uid_dir if uid_dir.is_dir() else None))
        conf = self.runtime / "sway.conf"
        conf.write_text(f"output HEADLESS-1 resolution {self.size[0]}x{self.size[1]}\n")
        env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "DISPLAY", "SWAYSOCK", "NIRI_SOCKET")}
        env.update(XDG_RUNTIME_DIR=str(self.runtime), WLR_BACKENDS="headless", WLR_RENDERER="pixman",
                   WLR_LIBINPUT_NO_DEVICES="1")
        self.log = open(self.runtime / "sway.log", "w")
        self.proc = subprocess.Popen([shutil.which("sway"), "-c", str(conf)], env=env,
                                     stdout=self.log, stderr=subprocess.STDOUT)
        for _ in range(100):
            sockets = sorted(p.name for p in self.runtime.glob("wayland-*") if not p.name.endswith(".lock"))
            if sockets:
                self.display = sockets[0]
                return self
            if self.proc.poll() is not None:
                break
            time.sleep(0.05)
        self.__exit__()
        raise RuntimeError("headless sway did not start: " + (self.runtime / "sway.log").read_text()[-500:])

    def env(self, extra=None):
        env = {k: v for k, v in os.environ.items() if k not in ("DISPLAY", "SWAYSOCK", "NIRI_SOCKET")}
        env.update(XDG_RUNTIME_DIR=str(self.runtime), WAYLAND_DISPLAY=self.display, QT_QPA_PLATFORM="wayland")
        env.update(extra or {})
        return env

    def msg(self, *args):
        """swaymsg output parsed as JSON."""
        sock = next(self.runtime.glob("sway-ipc.*.sock"))
        r = subprocess.run([shutil.which("swaymsg"), *args], env=dict(self.env(), SWAYSOCK=str(sock)),
                           capture_output=True, text=True, timeout=5)
        return json.loads(r.stdout or "null")

    def __exit__(self, *exc):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.log.close()
        shutil.rmtree(self.runtime, ignore_errors=True)


def run_wayland_smoke(screenshot=None):
    """Start shell/shell.qml under headless sway, toggle Quick Settings over IPC, and collect problems.

    Returns (code, report). brightnessctl is the fake in tests/qs/bin, so the real backlight is never touched.
    """
    qs, sway = shutil.which("quickshell"), shutil.which("sway")
    if not qs or not sway:
        return SKIPPED, "needs quickshell and sway"
    shell = ROOT / "shell" / "shell.qml"
    problems, notes = [], []
    with HeadlessSway() as comp, PrivateBus() as bus:
        fake = comp.runtime / "fake-brightness"
        env = comp.env({
            "PATH": f"{ROOT / 'tests' / 'qs' / 'bin'}:{os.environ.get('PATH', '')}",
            "FAKE_BRIGHTNESS": str(fake),
            "FAKE_APP_LOG": str(comp.runtime / "apps.log"),
            "RUTILE_ANIMATION_SPEED": "1.5",
            "DBUS_SESSION_BUS_ADDRESS": bus.address,
            # never the user's settings or state (D45)
            "XDG_CONFIG_HOME": str(comp.runtime / "config"),
            "XDG_STATE_HOME": str(comp.runtime / "state"),
            # only the fixture apps, so the shelf's default pins are known
            "XDG_DATA_DIRS": str(ROOT / "tests" / "qs" / "apps"),
            "XDG_DATA_HOME": str(ROOT / "tests" / "qs" / "apps" / "no-user-apps"),
            "RUTILE_PALETTE": str(ROOT / "theme" / "fixtures" / "palette-134aae-tonal-spot-dark.json"),
        })
        log_path = comp.runtime / "shell.log"
        with open(log_path, "w") as log:
            shell_proc = subprocess.Popen([qs, "-p", str(shell)], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(*args, target="quicksettings"):
                    r = subprocess.run([qs, "-p", str(shell), "ipc", "call", target, *args],
                                       env=env, capture_output=True, text=True, timeout=10)
                    return (r.stdout + r.stderr).strip()
                deadline = time.time() + 15
                while "Configuration Loaded" not in log_path.read_text() and time.time() < deadline:
                    if shell_proc.poll() is not None:
                        break
                    time.sleep(0.1)
                if "Configuration Loaded" not in log_path.read_text():
                    problems.append("the shell did not load")
                else:
                    # the animation speed (D43) comes from the environment; setSpeed saves the setting (D45)
                    for args, want in [(("speed",), "1.5"), (("setSpeed", "2"), "true"), (("speed",), "2"),
                                       (("setSpeed", "9"), "false"), (("speed",), "2")]:
                        got = ipc(*args, target="motion")
                        if got != want:
                            problems.append(f"ipc motion {' '.join(args)}: got {got!r}, expected {want!r}")
                    saved = comp.runtime / "config" / "rutile" / "settings.json"
                    try:
                        speed = json.loads(saved.read_text())["motion"]["speed"]
                    except (OSError, ValueError, KeyError) as e:
                        speed = repr(e)
                    if speed != 2:
                        problems.append(f"settings.json after setSpeed 2: motion.speed is {speed}, expected 2")
                    steps = [("isOpen", "false"), ("toggle", ""), ("isOpen", "true")]
                    for call, want in steps:
                        got = ipc(call)
                        if got != want:
                            problems.append(f"ipc {call}: got {got!r}, expected {want!r}")
                        time.sleep(0.5)
                    time.sleep(1.0)
                    # what the windows see: the panel reaches the backend (the fake brightness shows as a
                    # slider) and the pill on the panel's screen is marked open
                    try:
                        state = json.loads(ipc("state"))
                    except ValueError as e:
                        state = {}
                        problems.append(f"ipc state: {e}")
                    # the clock shows the time and date from SystemClock ("8:55 Fri, Oct 9"; the minute varies)
                    clocks = state.pop("clocks", None)
                    if not (isinstance(clocks, list) and len(clocks) == 1
                            and re.fullmatch(r"\d{1,2}:\d\d \S+, \S+ \d{1,2}", clocks[0])):
                        problems.append(f"ipc state: clocks {clocks!r}, expected one time and date")
                    else:
                        # and it is now (12- or 24-hour, either of the last two minutes)
                        h, m = map(int, clocks[0].split()[0].split(":"))
                        nows = [time.localtime(time.time() - d) for d in (0, 60)]
                        if not any(h % 12 == t.tm_hour % 12 and m == t.tm_min for t in nows):
                            problems.append(f"ipc state: clock {clocks[0]!r} is not the current time")
                    shelves = state.pop("shelves", None)
                    # the fixture's default pins; no niri and no windows here, so no workspace groups
                    if shelves != [{"pinned": ["org.gnome.Nautilus", "firefox", "foot"], "workspaces": []}]:
                        problems.append(f"ipc state: shelves {shelves!r}, expected the fixture's default pins")
                    want = {"open": True, "loaded": True, "panelHasBackend": True, "brightnessShown": True, "darkTheme": True, "pillsOpen": [True],
                            "pillsHaveBackend": [True], "pillsOnTop": [True], "reserved": [32]}
                    if state != want:
                        problems.append(f"ipc state: got {state}, expected {want}")
                    # the compositor keeps windows out of the reserved strip: sway's workspace starts below it
                    spaces = comp.msg("-t", "get_workspaces") or []
                    tops = [w["rect"]["y"] for w in spaces]
                    if tops != [32]:
                        problems.append(f"workspace area starts at {tops}, expected [32] (the pill's reserved space)")
                    # and ends above the shelf (48 px at the bottom of the 800 px output)
                    bottoms = [w["rect"]["y"] + w["rect"]["height"] for w in spaces]
                    if bottoms != [800 - 48]:
                        problems.append(f"workspace area ends at {bottoms}, expected [{800 - 48}] (above the shelf)")
                    if screenshot:
                        grim = shutil.which("grim")
                        if grim:
                            subprocess.run([grim, str(screenshot)], env=comp.env(), timeout=10)
                            notes.append(f"screenshot: {screenshot}")
                        else:
                            notes.append("no screenshot: grim not found")
                    for call, want in [("toggle", ""), ("isOpen", "false"), ("open", ""), ("isOpen", "true"),
                                       ("close", ""), ("isOpen", "false")]:
                        got = ipc(call)
                        if got != want:
                            problems.append(f"ipc {call}: got {got!r}, expected {want!r}")
                    # the launcher: opens over IPC with the fixture apps, ranks a query, closes and unloads
                    for args, want in [(("isOpen",), "false"), (("toggle",), ""), (("isOpen",), "true"),
                                       (("search", "fire"), "firefox"), (("search", "fot"), "foot"),
                                       (("search", "term"), "foot"), (("search", "qqqq"), "")]:
                        got = ipc(*args, target="launcher")
                        if args[0] == "search":
                            got = got.split(",")[0]         # the best match
                        if got != want:
                            problems.append(f"ipc launcher {' '.join(args)}: got {got!r}, expected {want!r}")
                    try:
                        launcher = json.loads(ipc("state", target="launcher"))
                    except ValueError:
                        launcher = {}
                    want = {"open": True, "loaded": True, "apps": 3, "listView": False,
                            "categories": ["internet", "system", "utilities"], "used": []}
                    if launcher != want:
                        problems.append(f"ipc launcher state: {launcher}, expected {want} (the 3 fixture apps)")
                    # grid or list is remembered in state.json (D45)
                    ipc("setListView", "true", target="launcher")
                    state_file = comp.runtime / "state" / "rutile" / "state.json"
                    for _ in range(20):
                        if state_file.exists():
                            break
                        time.sleep(0.1)
                    try:
                        view = json.loads(state_file.read_text())["launcher"]["view"]
                    except (OSError, ValueError, KeyError) as e:
                        view = repr(e)
                    if view != "list" or json.loads(ipc("state", target="launcher") or "{}").get("listView") is not True:
                        problems.append(f"ipc launcher setListView true: state.json has {view}, expected list")
                    ipc("setListView", "false", target="launcher")
                    # the chips: the desktop files' Categories
                    for args, want in [(("category", "system"), "foot"), (("category", "internet"), "firefox"),
                                       (("category", ""), "org.gnome.Nautilus,firefox,foot")]:
                        ipc("search", "", target="launcher")
                        got = ipc(*args, target="launcher")
                        if got != want:
                            problems.append(f"ipc launcher {' '.join(args)}: got {got!r}, expected {want!r}")
                    # a desktop action, as the app menu runs it: the launcher runs it and closes
                    got = ipc("actions", "firefox", target="launcher")
                    if got != "new-private-window":
                        problems.append(f"ipc launcher actions firefox: got {got!r}, expected 'new-private-window'")
                    ipc("chooseAction", "firefox", "new-private-window", target="launcher")
                    app_log = comp.runtime / "apps.log"
                    for _ in range(50):
                        if app_log.exists():
                            break
                        time.sleep(0.1)
                    ran = app_log.read_text().strip() if app_log.exists() else None
                    if ran != "firefox --private-window":
                        problems.append(f"launcher action: ran {ran!r}, expected 'firefox --private-window'")
                    if ipc("isOpen", target="launcher") != "false":
                        problems.append("launcher action: the launcher stayed open")
                    time.sleep(1.5)
                    # what was opened counts toward its usage, in state.json (Usage.js)
                    try:
                        uses = json.loads(state_file.read_text())["launcher"]["usage"]["firefox"]["count"]
                    except (OSError, ValueError, KeyError) as e:
                        uses = repr(e)
                    if uses != 1:
                        problems.append(f"launcher usage of firefox after its action: {uses}, expected 1")
                    ipc("open", target="launcher")
                    # Unpin saves the pins shown (the fixture's defaults) without that app (D45)
                    got = ipc("togglePin", "foot", target="launcher")
                    for _ in range(20):                     # the write is asynchronous
                        try:
                            pins = json.loads(saved.read_text())["shelf"]["pins"]
                        except (OSError, ValueError, KeyError) as e:
                            pins = repr(e)
                        if pins == ["org.gnome.Nautilus", "firefox"]:
                            break
                        time.sleep(0.1)
                    if got != "true" or pins != ["org.gnome.Nautilus", "firefox"]:
                        problems.append(f"ipc launcher togglePin foot: {got}, pins {pins}, expected Nautilus and firefox")
                    # the reopened launcher ranks with the usage; opening an app by click counts too
                    try:
                        used = json.loads(ipc("state", target="launcher")).get("used")
                    except ValueError:
                        used = None
                    if used != ["firefox"]:
                        problems.append(f"ipc launcher state: used {used!r} after reopening, expected ['firefox']")
                    got = ipc("launch", "foot", target="launcher")
                    time.sleep(0.5)
                    try:
                        foot = json.loads(state_file.read_text())["launcher"]["usage"]["foot"]["count"]
                    except (OSError, ValueError, KeyError) as e:
                        foot = repr(e)
                    if got != "true" or foot != 1 or ipc("isOpen", target="launcher") != "false":
                        problems.append(f"ipc launcher launch foot: {got}, usage {foot}, expected 1 and the launcher closed")
                    time.sleep(1.5)
                    # Quick Settings' controls are search results: a toggle flips, a slider opens Quick Settings
                    def qs_state():
                        try:
                            return json.loads(ipc("state"))
                        except ValueError:
                            return {}
                    dark = qs_state().get("darkTheme")
                    ipc("open", target="launcher")
                    found = ipc("search", "dark theme", target="launcher").split(",")[0]
                    got = ipc("launch", "qs:dark", target="launcher")
                    time.sleep(0.3)
                    if found != "qs:dark" or got != "true" or qs_state().get("darkTheme") is not (not dark):
                        problems.append(f"launcher setting qs:dark: found {found!r}, launch {got}, dark theme "
                                        f"{qs_state().get('darkTheme')!r}, expected it flipped from {dark!r}")
                    if ipc("isOpen", target="launcher") != "false":
                        problems.append("launcher setting qs:dark: the launcher stayed open")
                    if ipc("isOpen") != "false":
                        problems.append("launcher setting qs:dark: a toggle opened Quick Settings")
                    time.sleep(1.5)
                    ipc("open", target="launcher")
                    found = ipc("search", "backlight", target="launcher").split(",")[0]
                    ipc("launch", "qs:brightness", target="launcher")
                    time.sleep(0.3)
                    if found != "qs:brightness" or ipc("isOpen") != "true":
                        problems.append(f"launcher setting qs:brightness: found {found!r}, Quick Settings open "
                                        f"{ipc('isOpen')!r}, expected it opened")
                    ipc("close")
                    time.sleep(1.5)
                    ipc("open", target="launcher")
                    # slow motion, so the launcher is still on screen when asked: closing, not open
                    ipc("setSpeed", "0.1", target="motion")
                    ipc("close", target="launcher")
                    closing = (ipc("isOpen", target="launcher"), ipc("state", target="launcher"))
                    if closing[0] != "false" or '"loaded":true' not in closing[1]:
                        problems.append(f"ipc launcher close: {closing}, expected closed while its motion plays")
                    ipc("setSpeed", "2", target="motion")
                    # closing plays the panel's motion, then the loader drops the window (`open` above went
                    # false at once; `open` right after `toggle` reopened it mid-close)
                    time.sleep(1.5)
                    try:
                        loaded = json.loads(ipc("state")).get("loaded")
                    except ValueError:
                        loaded = None
                    if loaded is not False:
                        problems.append(f"ipc state: loaded {loaded!r} after closing, expected False")
                    try:
                        launcher_loaded = json.loads(ipc("state", target="launcher")).get("loaded")
                    except ValueError:
                        launcher_loaded = None
                    if launcher_loaded is not False:
                        problems.append(f"ipc launcher state: loaded {launcher_loaded!r} after closing, expected False")
                    # a notification (plan 2.8) on the private bus: kept, popped up in its window, gone when dismissed
                    # notify-send (libnotify, as apps send) when the dev shell has it, else busctl
                    if shutil.which("notify-send"):
                        notify = ["notify-send", "--app-name=Mail", "--expire-time=0", "Hello", "<b>from</b> the smoke test"]
                    else:
                        notify = [shutil.which("busctl") or "busctl", "--user", "--", "call", "org.freedesktop.Notifications",
                                  "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify",
                                  "susssasa{sv}i", "Mail", "0", "", "Hello", "<b>from</b> the smoke test", "0", "0", "0"]
                        notes.append("busctl sent the notification: notify-send not found")
                    sent = subprocess.run(notify, env=env, capture_output=True, text=True, timeout=10)
                    def notification_state():
                        try:
                            return json.loads(ipc("state", target="notifications"))
                        except ValueError:
                            return {}
                    for _ in range(20):
                        n = notification_state()
                        if n.get("shown"):
                            break
                        time.sleep(0.1)
                    want_list = [{"id": 1, "app": "Mail", "summary": "Hello", "body": "from the smoke test"}]
                    if sent.returncode != 0 or n.get("list") != want_list or n.get("shown") != [1] or not n.get("windowLoaded"):
                        problems.append(f"notification: busctl {sent.returncode} {sent.stderr.strip()!r}, state {n}, "
                                        f"expected {want_list} shown in a loaded window")
                    if screenshot:
                        grim = shutil.which("grim")
                        if grim:
                            time.sleep(1)               # the popup's motion
                            shot = Path(screenshot).with_name(Path(screenshot).stem + "-notification.png")
                            subprocess.run([grim, str(shot)], env=comp.env(), timeout=10)
                            notes.append(f"screenshot: {shot}")
                    # one whose popup times out stays in the list (the maintainer's report: check it does)
                    if shutil.which("notify-send"):
                        subprocess.run(["notify-send", "--expire-time=300", "Brief", "goes from the screen"],
                                       env=env, capture_output=True, timeout=10)
                        time.sleep(1.5)
                        n = notification_state()
                        if [x["summary"] for x in n.get("list", [])] != ["Brief", "Hello"] or n.get("popups") != [1]:
                            problems.append(f"a timed-out popup: state {n}, expected Brief kept in the list, only 1 popping up")
                    # an inline reply reaches the sender (NotificationReplied on the bus)
                    busctl = shutil.which("busctl")
                    if busctl:
                        mon_log = comp.runtime / "bus.log"
                        with open(mon_log, "w") as ml:
                            mon = subprocess.Popen([busctl, "--user", "monitor"], env=env, stdout=ml, stderr=subprocess.STDOUT)
                            time.sleep(0.5)
                            r = subprocess.run([busctl, "--user", "--", "call", "org.freedesktop.Notifications",
                                                "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify",
                                                "susssasa{sv}i", "Chat", "0", "", "Hi", "there", "2", "inline-reply",
                                                "Message", "0", "-1"], env=env, capture_output=True, text=True, timeout=10)
                            chat = int(r.stdout.split()[-1]) if r.returncode == 0 else -1
                            time.sleep(0.3)
                            ipc("reply", str(chat), "hello back", target="notifications")
                            time.sleep(0.5)
                            mon.terminate()
                            mon.wait(timeout=5)
                        bus_text = mon_log.read_text()
                        if "Member=NotificationReplied" not in bus_text or '"hello back"' not in bus_text:
                            problems.append("inline reply: no NotificationReplied with the text on the bus")
                    # the bell shows there is one; it opens the list, and Do not disturb crosses it out (D47)
                    if n.get("bells") != ["notifications_unread"]:
                        problems.append(f"notification bell: {n.get('bells')}, expected ['notifications_unread']")
                    ipc("toggle", target="notifications")
                    time.sleep(0.5)
                    n = notification_state()
                    if not n.get("listOpen") or n.get("listShown")[-1:] != [1] or n.get("popups") != [] or n.get("bellsOpen") != [True]:
                        problems.append(f"ipc notifications toggle: {n}, expected the list open with notification 1, "
                                        "and no popups")
                    if screenshot and shutil.which("grim"):
                        time.sleep(1)
                        shot = Path(screenshot).with_name(Path(screenshot).stem + "-notification-list.png")
                        subprocess.run([shutil.which("grim"), str(shot)], env=comp.env(), timeout=10)
                        notes.append(f"screenshot: {shot}")
                    # toggled again while it closes, it grows back
                    ipc("setSpeed", "0.2", target="motion")
                    ipc("toggle", target="notifications")
                    ipc("toggle", target="notifications")
                    time.sleep(0.3)
                    n = notification_state()
                    ipc("setSpeed", "2", target="motion")
                    if not n.get("listOpen") or not n.get("listLoaded"):
                        problems.append(f"ipc notifications toggle while closing: {n}, expected it open again")
                    ipc("toggle", target="notifications")
                    time.sleep(1.5)
                    if notification_state().get("listLoaded") is not False:
                        problems.append("ipc notifications toggle again: the list stayed loaded")
                    ipc("setDnd", "true", target="notifications")
                    if notification_state().get("bells") != ["notifications_off"]:
                        problems.append(f"Do not disturb: bell {notification_state().get('bells')}, expected notifications_off")
                    ipc("setDnd", "false", target="notifications")
                    ipc("dismissAll", target="notifications")
                    time.sleep(1.5)
                    n = notification_state()
                    if n.get("list") != [] or n.get("windowLoaded") is not False or n.get("bells") != ["notifications"]:
                        problems.append(f"notification dismissed: state {n}, expected none and the window unloaded")
                    # Closing when another window takes focus (D41) cannot be tested here: sway gives an
                    # on-demand layer surface focus only when it is clicked, and there is no pointer.
                    calls = (fake.parent / (fake.name + ".log"))
                    if not calls.exists() or "info" not in calls.read_text():
                        problems.append("opening the panel did not read the brightness")
            finally:
                shell_proc.terminate()
                try:
                    shell_proc.wait(5)
                except subprocess.TimeoutExpired:
                    shell_proc.kill()
        text = log_path.read_text()
    # QML errors and warnings from our files; service connection errors are expected here (no PipeWire,
    # no BlueZ in the private runtime dir) and are not ours.
    for line in text.splitlines():
        if re.search(r"(ERROR|WARN).*(@|file://).*\.qml|TypeError|ReferenceError|is not defined|Unable to assign", line):
            problems.append(line.strip())
    return (1 if problems else 0), "\n".join(problems + notes)


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
        # qmllint exits 0 on some warnings (id-shadows-member, incompatible-type); any warning fails the gate
        code = proc.returncode or (1 if "Warning:" in out else 0)
        return code, out + (hint(out) if code else "")
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
    if argv and argv[0] == "test-gpu":
        code, out, counts = run_tests(gpu=True)
        if code == SKIPPED:
            print(f"gpu tests: SKIPPED, {out}")
            return 0
        print(out if code else f"gpu tests passed {counts}")
        return code
    if argv and argv[0] == "test-wayland":
        shot = argv[argv.index("--screenshot") + 1] if "--screenshot" in argv else None
        code, out = run_wayland_smoke(shot)
        if code == SKIPPED:
            print(f"wayland smoke test: SKIPPED, {out}")
            return 0
        print(out if out else "wayland smoke test passed")
        return code
    if argv and argv[0] == "test-qs":
        code, out, counts = run_qs_tests()
        if code == SKIPPED:
            print(f"quickshell tests: SKIPPED, {out}")
            return 0
        print(out if code else f"quickshell tests passed {counts}")
        return code
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
