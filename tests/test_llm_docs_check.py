import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import llm_docs_check as ld  # noqa: E402


def full_docs():
    """Documents that list everything the checker wants, generated from the real source."""
    tokens = ["# Tokens", "Colors roles: `on_primary` is written `Colors.primaryOn` (QML reads onX as a handler)."]
    for s in ld.SINGLETONS:
        tokens += [f"## {s}", "| name |", "|---|"] + [f"| `{m}` |" for m in ld.members(ld.COMMON / f"{s}.qml")]
    tokens += ["```qml\nSurface { tone: Colors.surfaceContainer; radius: Shapes.medium }\n```"] * 6
    comps = ["# Components"]
    for c in ld.components():
        comps += [f"## {c}"] + [f"- `{m}`" for m in ld.members(ld.COMPONENTS / f"{c}.qml", ld.PUBLIC)]
    comps.append("```qml\nButton { text: \"Save\"; type: \"tonal\" }\n```")
    return "\n".join(tokens) + "\n", "\n".join(comps) + "\n"


class LlmDocsCheck(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.old = ld.DOCS
        ld.DOCS = self.tmp
        self.addCleanup(setattr, ld, "DOCS", self.old)
        self.tokens, self.comps = full_docs()

    def run_check(self, tokens=None, comps=None):
        (self.tmp / "TOKENS.md").write_text(self.tokens if tokens is None else tokens)
        (self.tmp / "COMPONENTS.md").write_text(self.comps if comps is None else comps)
        out = io.StringIO()
        return ld.main([], out=out), out.getvalue()

    def test_complete_documents_pass(self):
        code, out = self.run_check()
        self.assertEqual(code, 0, out)

    def test_members_come_from_the_real_source(self):
        self.assertIn("primaryOn", ld.members(ld.COMMON / "Colors.qml"))
        self.assertIn("medium", ld.members(ld.COMMON / "Shapes.qml"))
        self.assertEqual(ld.members(ld.COMPONENTS / "Surface.qml", ld.PUBLIC), ["tone"])
        self.assertIn("Button", ld.components())

    def test_each_rule_catches_its_violation(self):
        cases = {
            "lacks 1 member(s): medium": dict(tokens=self.tokens.replace("| `medium` |\n", "", 1)),
            "no section (heading) for Spacing": dict(tokens=self.tokens.replace("## Spacing", "Spacing:")),
            "must state that on_primary": dict(tokens=self.tokens.replace("primaryOn", "x")),
            "needs at least 6": dict(tokens=self.tokens.replace("```qml", "```text", 1)),
            "hardcoded color #ff0000": dict(tokens=self.tokens + "```qml\nRectangle { color: \"#ff0000\" }\n```\n"),
            "numeric radius": dict(tokens=self.tokens + "```qml\nRectangle { radius: 12 }\n```\n"),
            "numeric duration": dict(tokens=self.tokens + "```qml\nNumberAnimation { duration: 200 }\n```\n"),
            "Colors.primaryOnn does not exist": dict(tokens=self.tokens + "```qml\nText { color: Colors.primaryOnn }\n```\n"),
            "unknown component FancyCard": dict(comps=self.comps + "```qml\nFancyCard { }\n```\n"),
            "Surface section lacks: tone": dict(comps=self.comps.replace("- `tone`\n", "")),
            "TOKENS.md: file not found": dict(tokens=None),
        }
        for needle, kw in cases.items():
            if kw.get("tokens", "") is None:
                (self.tmp / "COMPONENTS.md").write_text(self.comps)
                (self.tmp / "TOKENS.md").unlink(missing_ok=True)
                out = io.StringIO()
                code, text = ld.main([], out=out), out.getvalue()
            else:
                code, text = self.run_check(**kw)
            self.assertEqual(code, 1, needle)
            self.assertIn(needle, text, needle)


if __name__ == "__main__":
    unittest.main()
