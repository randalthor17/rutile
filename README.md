# Rutile Shell

A Quickshell-based desktop shell for niri that recreates the Googlebook /
ChromeOS look using Material 3 Expressive, with a settings app and desktop
widgets that a local LLM (Ollama / Gemma) can create from a documented spec.

Status: **0.1.0, foundations only.** There is no QML yet; this release has the
design tokens and the checks every later commit has to pass.

## Layout

| Path | Purpose |
|---|---|
| `tokens/` | M3E tokens: vendored sources, checksums, generated `m3e.json` |
| `tools/` | `gen_tokens.py`, `lint_hardcoded.py` |
| `tests/` | unit tests (stdlib `unittest`) |
| `shell/` `settings/` `widgets/` `nix/` `docs/` | empty for now, see roadmap |

## Checks

    make check     # token freshness, tests, hardcoded-value lint, qmllint

`qmllint` only runs when QML exists and the tool is installed; otherwise it says
it was skipped. Visual and compositor behavior can only be verified on a real
niri session.

## Tokens

`tokens/m3e.json` holds shape corners, motion springs (expressive and standard),
durations, easings, elevation and the type scale including emphasized styles.
It is generated from androidx Compose Material3 token sources, not scraped from
m3.material.io. Change tokens by refreshing sources (`tools/gen_tokens.py
--refresh`), reviewing the diff and regenerating, never by editing the JSON.

Colors are not here: they come from matugen at runtime.

## License

MIT, see `LICENSE`. Third-party notices are in `NOTICE`.
