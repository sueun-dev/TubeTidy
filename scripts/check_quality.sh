#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  eval "$(
    ROOT_DIR="$ROOT_DIR" python3 - <<'PY'
from pathlib import Path
import os
import shlex

env_path = Path(os.environ['ROOT_DIR']) / '.env'
for line in env_path.read_text().splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith('#') or '=' not in stripped:
        continue
    key, value = stripped.split('=', 1)
    print(f"export {key.strip()}={shlex.quote(value.strip())}")
PY
  )"
fi

if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
elif [[ -x /tmp/flutter-sdk/bin/flutter ]]; then
  FLUTTER_BIN="/tmp/flutter-sdk/bin/flutter"
else
  echo "flutter binary not found" >&2
  exit 1
fi

DART_BIN="$(cd "$(dirname "$FLUTTER_BIN")" && pwd)/dart"
PYTHON_BIN="$ROOT_DIR/.venv/bin/python"

if [[ ! -x "$PYTHON_BIN" ]]; then
  python3 -m venv "$ROOT_DIR/.venv"
fi

if ! "$PYTHON_BIN" -m pylint --version >/dev/null 2>&1; then
  "$PYTHON_BIN" -m pip install -r "$ROOT_DIR/server/requirements-dev.txt"
fi

DB_TEST_URL="${DATABASE_URL_UNPOOLED:-${DATABASE_URL:-}}"

echo "[1/6] dart format"
"$DART_BIN" format --output=none --set-exit-if-changed \
  "$ROOT_DIR/lib" \
  "$ROOT_DIR/test" \
  "$ROOT_DIR/integration_test"

echo "[2/6] flutter analyze"
CI=true "$FLUTTER_BIN" analyze

echo "[3/6] flutter test"
CI=true "$FLUTTER_BIN" test

echo "[4/6] pylint"
"$PYTHON_BIN" -m pylint \
  "$ROOT_DIR/server" \
  "$ROOT_DIR/scripts/migrate_db.py"

echo "[5/6] python unit tests"
if [[ -n "$DB_TEST_URL" ]]; then
  DATABASE_URL="$DB_TEST_URL" \
    "$PYTHON_BIN" -m unittest discover -s "$ROOT_DIR/server/tests"
else
  "$PYTHON_BIN" -m unittest discover -s "$ROOT_DIR/server/tests"
fi

if [[ -n "$DB_TEST_URL" ]]; then
  echo "[6/6] db migration + integration tests"
  DATABASE_URL="$DB_TEST_URL" "$PYTHON_BIN" "$ROOT_DIR/scripts/migrate_db.py"
  DATABASE_URL="$DB_TEST_URL" \
    "$PYTHON_BIN" -m unittest server.tests.test_db_integration
else
  echo "[6/6] db integration skipped (DATABASE_URL not configured)"
fi
