# Conventions for the local model

You are working on Rutile Shell, a Quickshell desktop shell for niri with a Googlebook-style
Material 3 Expressive look. You are on a `local/*` branch in your own worktree.

## Hard rules

- Only create or edit files under the paths your task brief lists. A commit that touches anything else
  is rejected by a hook, so do not try; if the task seems to need a change elsewhere, stop and say so.
- Never edit `tools/`, `flake.nix`, `Makefile`, `README.md`, `LICENSE`, `NOTICE` or anything in `shell/`,
  `tokens/`, `theme/`, `nix/`, `tests/`.
- Do not invent facts about the repo. When unsure what a token, component or property is called, read
  the source (`shell/common/*.qml`, `shell/components/*.qml`, `tokens/*.json`) instead of guessing.
- Do not add dependencies. Everything is stdlib or already in the repo.

## Style

- JSON: 2-space indent, double quotes, no comments, no trailing commas, sorted keys only where the
  brief says so. Files end with a newline.
- Markdown: plain, short paragraphs, tables only for real tables. No emojis.
- Design values are never hardcoded in QML: colors come from `Colors`, shapes from `Shapes`, motion
  from `Motion`, type from `Type`. Color roles are camelCase with `on_x` written `xOn`
  (`on_primary` is `primaryOn`), because QML reads `onXxx` as a signal handler.
- Component and widget names are lowercase words (`filled`, `tonal`, `round`), as in the specs.

## Working method

1. Read the task brief and the files it names before writing anything.
2. Make small commits, one concern each, with a one-line imperative message.
3. After each change, run the acceptance commands from the brief. Fix before moving on.
4. If `make check` fails, say what failed. Do not edit tests to make them pass.
5. When finished, summarize what changed and anything you were unsure about.
