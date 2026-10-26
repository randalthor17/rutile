"""The home-manager module (nix/home-manager.nix, D45): its options come from settings/schema.json, and what is
set lands in managed.json. Evaluated with nixpkgs from NIX_PATH and a stand-in for home-manager; skipped (loudly)
without nix or nixpkgs."""
import json
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVAL = ROOT / "tests" / "nix" / "hm-eval.nix"
MODULE = ROOT / "nix" / "home-manager.nix"


def evaluate(settings):
    """(managed.json as an object, or "none" when nothing is written; error text)"""
    expr = f"import {EVAL} {{ module = {MODULE}; settings = {settings}; }}"
    r = subprocess.run(["nix-instantiate", "--eval", "--strict", "--read-write-mode", "-E", expr],
                       capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        return None, r.stderr
    text = json.loads(r.stdout)          # a Nix string prints as a JSON string
    return (text if text == "none" else json.loads(text)), ""


def nixpkgs_available():
    if not shutil.which("nix-instantiate"):
        return False
    r = subprocess.run(["nix-instantiate", "--eval", "-E", "(import <nixpkgs> { }).lib.version"],
                       capture_output=True, text=True, timeout=120)
    return r.returncode == 0


@unittest.skipUnless(nixpkgs_available(), "SKIPPED: needs nix-instantiate and <nixpkgs> on NIX_PATH")
class HomeManagerModule(unittest.TestCase):
    def test_writes_only_what_is_set(self):
        got, err = evaluate("{ motion.speed = 1.5; }")
        self.assertEqual(got, {"motion": {"speed": 1.5}}, err)

    def test_lists_and_empty_lists(self):
        self.assertEqual(evaluate('{ shelf.pins = [ "foot" "firefox" ]; }')[0], {"shelf": {"pins": ["foot", "firefox"]}})
        self.assertEqual(evaluate("{ shelf.pins = [ ]; }")[0], {"shelf": {"pins": []}}, "an empty shelf is a choice")

    def test_nothing_set_writes_no_file(self):
        self.assertEqual(evaluate("{ }")[0], "none")

    def test_the_schema_limits_apply(self):
        for bad in ("{ motion.speed = 9; }", "{ motion.speed = -1; }", '{ motion.speed = "fast"; }',
                    "{ shelf.pins = [ 1 ]; }", "{ motion.nope = 1; }"):
            got, err = evaluate(bad)
            self.assertIsNone(got, bad)
            self.assertIn("error:", err, bad)

    def test_limits_are_inclusive(self):
        self.assertEqual(evaluate("{ motion.speed = 0; }")[0], {"motion": {"speed": 0}})
        self.assertEqual(evaluate("{ motion.speed = 4; }")[0], {"motion": {"speed": 4}})


if __name__ == "__main__":
    unittest.main()
