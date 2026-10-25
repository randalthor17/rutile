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
- Never install anything: no `pip`, no virtualenv, no `nix profile`/`nix shell`, no edits to `flake.nix`.
  The checks your brief names need nothing that is not already here. If a command is missing, stop and
  say so; do not work around it.
- Create and change files only with the write and edit tools, never through shell redirection (`>`,
  `tee`, `sed -i`). The edit tools are what keep you inside your paths.
- Stay in this worktree. Do not create other worktrees or work anywhere else.

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
4. When a check fails, read the first error and fix that one thing. If the same error comes back twice,
   stop editing: re-read the brief and the error, and plan the fix before the next attempt. After three
   failed attempts at one error, stop and report it instead of trying more variations.
5. Commit only your own paths: `git add <your paths>` and `git commit -m "..."`, never `git add -A`.
6. If `make check` fails, say what failed. Do not edit tests to make them pass.
7. When finished, summarize what changed and anything you were unsure about.
