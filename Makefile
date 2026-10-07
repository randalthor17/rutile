# Every commit must pass `make check`.
PY ?= python3

.PHONY: check tokens tokens-check test lint qmllint

check: tokens-check test lint qmllint

tokens:
	$(PY) tools/gen_tokens.py

tokens-check:
	$(PY) tools/gen_tokens.py --check

test:
	$(PY) -m unittest discover -s tests -v

lint:
	$(PY) tools/lint_hardcoded.py

# qmllint only runs when there is QML and the tool is installed.
qmllint:
	@files=$$(find shell settings -name '*.qml' 2>/dev/null); \
	if [ -z "$$files" ]; then echo "qmllint: no QML yet"; \
	elif command -v qmllint >/dev/null 2>&1; then qmllint $$files; \
	else echo "qmllint: not installed, SKIPPED (run it on your machine)"; fi
