# Tokens

Source of truth: `tokens/m3e.json` (generated, see README).

Rules for QML (enforced by `tools/lint_hardcoded.py` in `make check`):
no hex colors, numeric `radius:` or numeric `duration:` in `shell/` or
`settings/`. Use the token singletons instead (added in Phase 1.3).

Open question for Phase 1.3: Qt's `SpringAnimation` takes `spring` and
`damping` parameters, not M3's stiffness and damping ratio. The `Motion`
singleton needs a tested conversion (or a custom spring driver) so the M3E
feel carries over. The tokens are kept in M3 units until then.
