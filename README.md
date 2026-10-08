# Rutile Shell

A Quickshell-based desktop shell for niri that recreates the Googlebook /
ChromeOS look using Material 3 Expressive, with a settings app and desktop
widgets that a local LLM (Ollama / Gemma) can create from a documented spec.

Status: **0.2.0, foundations only.** There is no QML yet; this release has the
design tokens, the matugen palette pipeline and the checks every later commit
has to pass.

## Layout

| Path | Purpose |
|---|---|
| `tokens/` | M3E tokens: vendored sources, checksums, generated `m3e.json` |
| `theme/` | matugen config + template, role list, golden palette fixture |
| `tools/` | `gen_tokens.py`, `palette.py`, `lint_hardcoded.py` |
| `tests/` | unit tests (stdlib `unittest`) |
| `shell/` `settings/` `widgets/` `nix/` `docs/` | empty for now, see roadmap |

## Checks

    make check     # token freshness, tests, hardcoded-value lint, qmllint

Tests that need matugen or `materialyoucolor` (optional, test-only) skip with a
message when they are missing, so check the skipped count. `qmllint` only runs
when QML exists and the tool is installed; otherwise it says it was skipped. Visual and compositor behavior can only be verified on a real
niri session.

## Tokens

`tokens/m3e.json` holds shape corners, motion springs (expressive and standard),
durations, easings, elevation and the type scale including emphasized styles.
It is generated from androidx Compose Material3 token sources, not scraped from
m3.material.io. Change tokens by refreshing sources (`tools/gen_tokens.py
--refresh`), reviewing the diff and regenerating, never by editing the JSON.

Colors are not here: they come from matugen at runtime, see `docs/theme.md`
(which also records how matugen's output compares to the 2025 color spec).

## License

MIT, see `LICENSE`. Third-party notices are in `NOTICE`.
