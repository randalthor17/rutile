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
        self.assertEqual(code, 0, out[-3000:])
        self.assertIsNotNone(counts, "could not parse qmltestrunner totals")
        passed, failed, skipped = counts
        self.assertEqual((failed, skipped), (0, 0), out[-3000:])
        # Guards against a silently empty run (wrong input dir, import problems).
        self.assertGreaterEqual(passed, 30)

    def test_workspace_excludes_quickshell_files_and_declares_singletons(self):
        ws = qtws.workspace()
        try:
            qmldir = (ws / "imp" / "qmldir").read_text().splitlines()
            self.assertIn("singleton Colors Colors.qml", qmldir)
            self.assertIn("singleton Motion Motion.qml", qmldir)
            self.assertIn("Spring Spring.qml", qmldir)
            self.assertFalse((ws / "imp" / "PaletteWatcher.qml").exists())
        finally:
            import shutil
            shutil.rmtree(ws, ignore_errors=True)


@unittest.skipUnless(qtws.qt_tool("qmllint"), "qmllint not found (set RUTILE_QT_BIN); lint SKIPPED")
class QmlLint(unittest.TestCase):
    def test_qmllint_is_clean(self):
        code, out = qtws.run_lint()
        self.assertEqual(code, 0, out)


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
