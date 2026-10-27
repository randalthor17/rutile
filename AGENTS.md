# Instructions for AI agents and contributors

**If you are the local model working on a `local/*` branch:** ignore the rest of this file. Your instructions are
`docs/sidework/CONVENTIONS.md` and your task brief in `docs/sidework/tasks/`. You may only change the paths your
brief lists; a commit hook rejects anything else.

**Everyone else (Claude, other assistants, people):**

1. Read `docs/HANDOFF.md` first. It is the entry point: state, working agreement, environment, release protocol.
2. Then `docs/PLAN.md` (what is done and next), `docs/DECISIONS.md` (why), `docs/LESSONS.md` (traps already hit).
3. The gate for every commit is `make check`. Test for real: break the code on purpose and confirm the tests fail.
4. Never edit generated files (`shell/common/*` marked GENERATED, `tokens/*.json`); change the source and regenerate.
5. No hardcoded colors, radii or durations in QML; use the singletons. No new dependencies without approval.
   Keep the shell light on memory: create on demand, unload when closed (`docs/memory.md`, D31).
6. Record progress in `docs/PLAN.md` and `CHANGELOG.md` in the same commit, and in your memory if you have one.
7. Claude's commits use `user.name claude`, `user.email claude@anthropic.com`. Push to `origin`
   (https://github.com/randalthor17/rutile); tag-worthy commits also get a tag. A session that cannot push hands over
   a git bundle instead (`docs/HANDOFF.md`). Never move a tag that was pushed or delivered.
8. Say what you did not verify. Do not let green checks imply more than they covered.
