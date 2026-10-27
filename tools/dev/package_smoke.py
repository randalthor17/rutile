#!/usr/bin/env python3
"""Smoke-test the built package (nix build .#default) under a headless sway, in a sandbox HOME (D55):
it starts, IPC works through `rutile-shell`, the palette renders from a wallpaper inside the store copy (so
matugen is on its PATH and ../theme resolves), and its fonts are visible through its own fontconfig file.

    tools/dev/package_smoke.py /nix/store/...-rutile-shell-0.1.0     (make package-check builds and runs it)
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tests"))
import qtws  # noqa: E402
from test_palette import solid_png  # noqa: E402


def main(pkg):
    exe = str(Path(pkg) / "bin" / "rutile-shell")
    problems = []
    with qtws.HeadlessSway() as comp, qtws.PrivateBus() as bus:
        rt = comp.runtime
        env = comp.env({"DBUS_SESSION_BUS_ADDRESS": bus.address, "XDG_SESSION_ID": "", "HOME": str(rt / "home"),
                        "XDG_CONFIG_HOME": str(rt / "config"), "XDG_STATE_HOME": str(rt / "state"),
                        "XDG_CACHE_HOME": str(rt / "cache"), "XDG_DATA_HOME": str(rt / "data")})
        qtws.no_polkit_agent(rt / "config")          # the system bus is shared (D49)
        log_path = rt / "shell.log"
        with open(log_path, "w") as log:
            proc = subprocess.Popen([exe], env=env, stdout=log, stderr=subprocess.STDOUT)

            def ipc(*args):
                r = subprocess.run([exe, "ipc", "call", *args], env=env, capture_output=True, text=True, timeout=10)
                return (r.stdout + r.stderr).strip()
            try:
                for _ in range(150):
                    if "Configuration Loaded" in log_path.read_text():
                        break
                    time.sleep(0.1)
                else:
                    problems.append("the shell did not load")
                if not problems:
                    if ipc("motion", "speed") != "1":
                        problems.append("ipc motion speed did not answer 1")
                    if ipc("settings", "open", "wallpaper") != "true":
                        problems.append("ipc settings open wallpaper refused")
                    wall = rt / "green.png"
                    solid_png(wall, (40, 160, 60))
                    ipc("wallpaper", "set", str(wall))
                    state = {}
                    for _ in range(100):
                        state = json.loads(ipc("wallpaper", "state") or "{}")
                        if state.get("paletteFrom") == str(wall) or state.get("error"):
                            break
                        time.sleep(0.1)
                    if state.get("error") or state.get("paletteFrom") != str(wall):
                        problems.append(f"no palette from the wallpaper: {state}")
                    else:
                        primary = json.loads((rt / "cache" / "rutile" / "palette.json").read_text())["colors"]["dark"]["primary"]
                        rgb = [int(primary[i:i + 2], 16) for i in (1, 3, 5)]
                        if max(range(3), key=lambda i: rgb[i]) != 1:
                            problems.append(f"the palette from a green wallpaper is not green: {primary}")
            finally:
                proc.terminate()
                proc.wait(timeout=10)
        errors = [line for line in log_path.read_text().splitlines()
                  if re.search(r"\bERROR\b", line) and "pipewire" not in line]      # no PipeWire in the sandbox
        problems += [f"log: {line}" for line in errors[:5]]
    conf = re.search(r"FONTCONFIG_FILE='?(/nix/store/[^' ]+)", (Path(pkg) / "bin" / "rutile-shell").read_text())
    if not shutil.which("fc-list"):
        print("fonts: SKIPPED (no fc-list)")
    else:
        families = subprocess.run(["fc-list", ":", "family"], capture_output=True, text=True,
                                  env=dict(os.environ, FONTCONFIG_FILE=conf.group(1) if conf else "")).stdout
        for family in ("Google Sans Flex", "Material Symbols Rounded"):
            if family not in families:
                problems.append(f"font {family} not visible through the package's fontconfig")
    for p in problems:
        print("PROBLEM:", p)
    print("package smoke test: " + ("failed" if problems else "passed"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
