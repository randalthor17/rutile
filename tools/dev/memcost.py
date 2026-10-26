#!/usr/bin/env python3
"""Memory cost of a component: resident memory added per instance, measured offscreen.

    memcost.py Slider [Switch ...] [--count N] [--props 'value: 0.4']

Loads N and then 2N copies of each component into one offscreen window and reports
(RSS with 2N - RSS with N) / N, the median of a few runs. It uses Qt's GPU scene graph (on Mesa's
software rasterizer when there is no GPU), like a real session; MEMCOST_BACKEND=software measures
the software renderer instead, which caches every rounded rectangle as an image and so inflates
them. Numbers are for comparing implementations of the same thing, not absolute budgets.
"""
import argparse
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import qtws  # noqa: E402

QML = """import QtQuick
import qs.common
import qs.components
import qs.quicksettings

Window {
    width: 1200; height: 900; visible: true
    Flow {
        anchors.fill: parent
        Repeater {
            model: %(count)d
            delegate: %(name)s { %(props)s }
        }
    }
    Timer { interval: 1500; running: true; onTriggered: console.warn("READY") }
}
"""


def rss_kb(pid):
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1])
    return 0


def measure(name, count, props):
    qml = qtws.qt_tool("qml")
    if not qml:
        raise SystemExit("the `qml` tool was not found (run inside `nix develop`)")
    ws = qtws.workspace()
    f = ws / f"mem_{name}_{count}.qml"
    f.write_text(QML % {"name": name, "count": count, "props": props})
    dirs = [str(ws)] + qtws.qml_import_dirs(qml)
    env = qtws.qml_env(dirs, dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND=os.environ.get("MEMCOST_BACKEND", "rhi"),
                                     QT_FORCE_STDERR_LOGGING="1"))   # else console output goes to the journal
    cmd = [qml] + sum((["-I", d] for d in dirs), []) + [str(f)]
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    timer = threading.Timer(60, proc.kill)    # never hang on a component that fails to load
    timer.start()
    try:
        for line in proc.stdout:
            if "READY" in line:
                time.sleep(0.3)
                return rss_kb(proc.pid)
            if "rror" in line:
                print(line.rstrip(), file=sys.stderr)
        raise SystemExit(f"{name}: qml exited before it was ready")
    finally:
        timer.cancel()
        proc.kill()
        proc.wait()


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("names", nargs="+")
    p.add_argument("--count", type=int, default=200)
    p.add_argument("--props", default="")
    p.add_argument("--repeat", type=int, default=3, help="report the median of this many runs (RSS is noisy)")
    a = p.parse_args(argv)
    for name in a.names:
        # N against 2N, not 0 against N: the first instance pays one-time costs (fonts, glyph caches, type
        # compilation) that would otherwise be spread over every instance.
        runs = sorted((measure(name, 2 * a.count, a.props) - measure(name, a.count, a.props)) / a.count
                      for _ in range(a.repeat))
        print(f"{name:14s} {runs[len(runs) // 2]:8.1f} KiB per instance  (median of {a.repeat}, "
              f"range {runs[0]:.1f}..{runs[-1]:.1f}; {a.count} -> {2 * a.count} instances)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
