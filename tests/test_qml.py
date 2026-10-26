import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import qtws  # noqa: E402

HAVE_QT = qtws.qt_tool("qmltestrunner") is not None


@unittest.skipUnless(HAVE_QT, "qmltestrunner not found (set RUTILE_QT_BIN); QML tests SKIPPED")
class QmlSuite(unittest.TestCase):
    def test_qml_tests_pass_offscreen(self):
        code, out, counts = qtws.run_tests()
        self.assertEqual(code, 0, qtws.summarize(out) + "\n\n" + out[-1500:])
        self.assertIsNotNone(counts, "could not parse qmltestrunner totals")
        passed, failed, skipped = counts
        self.assertEqual(failed, 0, out[-3000:])
        # Only the optional font tests may skip (no icon font found, or a Qt without font.variableAxes).
        skip_lines = [l for l in out.splitlines() if l.startswith("SKIP")]
        self.assertEqual(len(skip_lines), skipped)
        for line in skip_lines:
            self.assertIn("FontFiles", line, "unexpected skip: " + line)
        # Guards against a silently empty run (wrong input dir, import problems).
        self.assertGreaterEqual(passed, 30)

    def test_workspace_adds_font_test_only_when_fonts_are_found(self):
        import json
        import os
        import shutil
        import tempfile
        fonts = json.loads((ROOT / "theme" / "fonts.json").read_text())
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, True)
        old = os.environ.get("RUTILE_FONT_DIRS")
        self.addCleanup(lambda: os.environ.__setitem__("RUTILE_FONT_DIRS", old) if old is not None
                        else os.environ.pop("RUTILE_FONT_DIRS", None))
        os.environ["RUTILE_FONT_DIRS"] = str(d)
        ws = qtws.workspace()
        try:
            self.assertFalse((ws / "tests" / "tst_fonts.qml").exists())
            self.assertEqual(json.loads((ws / "data" / "fontpaths.json").read_text()), {})
        finally:
            shutil.rmtree(ws, ignore_errors=True)
        (d / "x").mkdir()
        (d / "x" / fonts["text"]["file"]).write_bytes(b"not a real font")
        ws = qtws.workspace()
        try:
            self.assertTrue((ws / "tests" / "tst_fonts.qml").exists())
            paths = json.loads((ws / "data" / "fontpaths.json").read_text())
            self.assertEqual(list(paths), ["text"])
            self.assertTrue(paths["text"].endswith(fonts["text"]["file"]))
        finally:
            shutil.rmtree(ws, ignore_errors=True)

    def test_workspace_excludes_quickshell_files_and_declares_singletons(self):
        ws = qtws.workspace()
        try:
            qmldir = (ws / "qs" / "common" / "qmldir").read_text().splitlines()
            self.assertEqual(qmldir[0], "module qs.common")
            comps = (ws / "qs" / "components" / "qmldir").read_text().splitlines()
            self.assertEqual(comps[0], "module qs.components")
            self.assertIn("singleton Colors Colors.qml", qmldir)
            self.assertIn("singleton Motion Motion.qml", qmldir)
            self.assertIn("singleton Fonts Fonts.qml", qmldir)
            self.assertIn("Spring Spring.qml", qmldir)
            self.assertIn("module qs.gallery", (ws / "qs" / "gallery" / "qmldir").read_text().splitlines()[0])
            self.assertFalse((ws / "qs" / "common" / "PaletteWatcher.qml").exists())
        finally:
            import shutil
            shutil.rmtree(ws, ignore_errors=True)


@unittest.skipUnless(qtws.qt_tool("qmllint"), "qmllint not found (set RUTILE_QT_BIN); lint SKIPPED")
class QmlLint(unittest.TestCase):
    def test_qmllint_is_clean(self):
        code, out = qtws.run_lint()
        self.assertEqual(code, 0, out)


@unittest.skipUnless(HAVE_QT, "qmltestrunner not found (set RUTILE_QT_BIN); render tool test SKIPPED")
class RenderTool(unittest.TestCase):
    def png_size(self, path):
        import struct
        data = Path(path).read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n", path)
        return struct.unpack(">II", data[16:24])

    def test_render_produces_full_size_slices_in_both_modes(self):
        import shutil
        import tempfile
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, True)
        sizes = {}
        for mode in ("dark", "light"):
            code, out, slices = qtws.render_gallery(d, mode)
            self.assertEqual(code, 0, out[-2000:])
            self.assertIsNotNone(slices, out[-2000:])
            self.assertGreaterEqual(len(slices), 4)
            for p in slices:
                self.assertEqual(self.png_size(p), (1180, 900))
                self.assertGreater(Path(p).stat().st_size, 4000, f"{p} looks blank")
            sizes[mode] = [Path(p).read_bytes() for p in slices]
        # the two modes must actually look different
        self.assertNotEqual(sizes["dark"][0], sizes["light"][0])

    def test_render_cli_reports_skipped_without_qt_tools(self):
        import contextlib
        import io
        import os
        import tempfile
        old = os.environ.get("RUTILE_QT_BIN")
        os.environ["RUTILE_QT_BIN"] = tempfile.mkdtemp()
        try:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = qtws.main(["render", "--out", tempfile.mkdtemp()])
            self.assertEqual(code, 0)
            self.assertIn("render: SKIPPED", buf.getvalue())
        finally:
            if old is None:
                os.environ.pop("RUTILE_QT_BIN")
            else:
                os.environ["RUTILE_QT_BIN"] = old


class ImportDiscovery(unittest.TestCase):
    """The nix-shell failure: QML modules exist next to the tool but are not on its default path."""

    def make_prefix(self, rel):
        import tempfile
        root = Path(tempfile.mkdtemp())
        self.addCleanup(__import__("shutil").rmtree, root, True)
        (root / "bin").mkdir()
        tool = root / "bin" / "qmltestrunner"
        tool.write_text("")
        (root / rel / "QtQuick").mkdir(parents=True)
        return root, tool

    def setUp(self):
        import os
        self.old = os.environ.pop("RUTILE_QML_IMPORT", None)
        self.addCleanup(self.restore)

    def restore(self):
        import os
        os.environ.pop("RUTILE_QML_IMPORT", None)
        if self.old is not None:
            os.environ["RUTILE_QML_IMPORT"] = self.old

    def test_finds_nixpkgs_layout(self):
        root, tool = self.make_prefix("lib/qt-6/qml")
        self.assertEqual(qtws.qml_import_dirs(str(tool)), [str(root / "lib/qt-6/qml")])

    def test_finds_other_layouts(self):
        for rel in ("lib/qt6/qml", "lib/qml", "qml"):
            root, tool = self.make_prefix(rel)
            self.assertEqual(qtws.qml_import_dirs(str(tool)), [str(root / rel)], rel)

    def test_follows_symlinks_to_the_real_prefix(self):
        import tempfile
        root, tool = self.make_prefix("lib/qt-6/qml")
        links = Path(tempfile.mkdtemp())
        self.addCleanup(__import__("shutil").rmtree, links, True)
        (links / "qmltestrunner").symlink_to(tool)
        self.assertEqual(qtws.qml_import_dirs(str(links / "qmltestrunner")), [str(root / "lib/qt-6/qml")])

    def test_ignores_dirs_without_qtquick(self):
        import tempfile
        root = Path(tempfile.mkdtemp())
        self.addCleanup(__import__("shutil").rmtree, root, True)
        (root / "bin").mkdir()
        (root / "bin" / "qmltestrunner").write_text("")
        (root / "lib/qt-6/qml").mkdir(parents=True)
        self.assertEqual(qtws.qml_import_dirs(str(root / "bin" / "qmltestrunner")), [])

    def test_env_override_comes_first_and_is_deduplicated(self):
        import os
        root, tool = self.make_prefix("lib/qt-6/qml")
        found = str(root / "lib/qt-6/qml")
        os.environ["RUTILE_QML_IMPORT"] = os.pathsep.join(["/custom/a", found, "/custom/a"])
        self.assertEqual(qtws.qml_import_dirs(str(tool)), ["/custom/a", found])

    def test_qml_env_merges_and_keeps_existing_values(self):
        import os
        base = {"A": "1", "QML_IMPORT_PATH": os.pathsep.join(["/x", "/y"]), "QML2_IMPORT_PATH": "/z:/x".replace(":", os.pathsep)}
        env = qtws.qml_env(["/new", "/x"], base)
        want = os.pathsep.join(["/new", "/x", "/y", "/z"])
        self.assertEqual(env["QML_IMPORT_PATH"], want)
        self.assertEqual(env["QML2_IMPORT_PATH"], want)
        self.assertEqual(env["A"], "1")
        self.assertEqual(base["QML_IMPORT_PATH"], os.pathsep.join(["/x", "/y"]), "input must not be mutated")

    def test_qml_env_without_dirs_changes_nothing(self):
        self.assertEqual(qtws.qml_env([], {"A": "1"}), {"A": "1"})

    def test_hint_only_for_environment_failures(self):
        self.assertIn("RUTILE_QML_IMPORT", qtws.hint('module "QtQuick.Window" is not installed'))
        self.assertIn("RUTILE_QML_IMPORT", qtws.hint("Type TestCase unavailable"))
        self.assertEqual(qtws.hint("FAIL!  : Colors::test_known_values()"), "")
        # a missing qs.* module is our problem, not Qt's: no Qt-path advice
        self.assertEqual(qtws.hint('module "qs.common" is not installed'), "")


class Summarize(unittest.TestCase):
    SAMPLE = "\n".join([
        "PASS   : A::one()",
        "FAIL!  : Fonts::two() 'bodyLargeEmphasized width 296 should exceed 302' returned FALSE. ()",
        "   Loc: [/tmp/x/tst_fonts.qml(80)]",
        "PASS   : A::three()",
        "FAIL!  : Tokens::four() name",
        "   Actual   (): 0.14",
        "   Expected (): 0.15",
        "   Loc: [/tmp/x/tst_tokens.qml(123)]",
        "Totals: 1 passed, 2 failed, 0 skipped",
    ])

    def test_failures_come_first_with_their_details(self):
        text = qtws.summarize(self.SAMPLE)
        self.assertEqual(text.splitlines()[0].split()[0], "FAIL!")
        self.assertIn("should exceed 302", text)
        self.assertIn("tst_fonts.qml(80)", text)
        self.assertIn("Actual   (): 0.14", text)
        self.assertNotIn("PASS", text)
        self.assertNotIn("Totals", text)

    def test_no_failures_gives_nothing(self):
        self.assertEqual(qtws.summarize("PASS   : A::one()\nTotals: 1 passed, 0 failed"), "")

    def test_a_long_run_does_not_hide_the_failure(self):
        passes = "\n".join(f"PASS   : T::t{i}()" for i in range(500))
        long_output = self.SAMPLE + "\n" + passes          # the failure is followed by a long run of passes
        tail = long_output[-300:]
        self.assertNotIn("should exceed", tail)            # plain truncation would lose the message
        self.assertIn("should exceed", qtws.summarize(long_output))


class SkipPath(unittest.TestCase):
    """Without Qt tools the QML checks must skip loudly, never fail or pass silently."""

    def setUp(self):
        import os
        import tempfile
        self.old = os.environ.get("RUTILE_QT_BIN")
        self.empty = tempfile.mkdtemp()
        os.environ["RUTILE_QT_BIN"] = self.empty
        self.addCleanup(self.restore)

    def restore(self):
        import os
        import shutil
        shutil.rmtree(self.empty, ignore_errors=True)
        if self.old is None:
            os.environ.pop("RUTILE_QT_BIN", None)
        else:
            os.environ["RUTILE_QT_BIN"] = self.old

    def test_override_is_authoritative(self):
        self.assertIsNone(qtws.qt_tool("qmltestrunner"))
        self.assertIsNone(qtws.qt_tool("qmllint"))

    def test_run_functions_report_skipped(self):
        self.assertEqual(qtws.run_tests()[0], qtws.SKIPPED)
        self.assertEqual(qtws.run_lint()[0], qtws.SKIPPED)

    def test_cli_fails_on_any_failure_count(self):
        # qmltestrunner exits with the number of failures; 3 once read as "skipped" and exited 0.
        import contextlib
        import io
        real = qtws.run_tests
        self.addCleanup(setattr, qtws, "run_tests", real)
        for failures in (1, 3, 255):
            qtws.run_tests = lambda *a, n=failures, **k: (n, "FAIL!", (10, n, 0))
            with contextlib.redirect_stdout(io.StringIO()):
                for cmd in (["test"], ["test-gpu"]):
                    self.assertEqual(qtws.main(cmd), failures, cmd)

    def test_cli_skips_with_message_and_exit_zero(self):
        import contextlib
        import io
        for cmd, word in (("lint", "qmllint: SKIPPED"), ("test", "qml tests: SKIPPED")):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = qtws.main([cmd])
            self.assertEqual(code, 0)
            self.assertIn(word, buf.getvalue())


if __name__ == "__main__":
    unittest.main()
