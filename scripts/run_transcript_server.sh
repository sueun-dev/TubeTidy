#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ ! -d "$ROOT_DIR/.venv" ]]; then
  python3 -m venv "$ROOT_DIR/.venv"
fi
source "$ROOT_DIR/.venv/bin/activate"

REQ_FILE="$ROOT_DIR/server/requirements.txt"
REQ_STAMP="$ROOT_DIR/.venv/.transcript_requirements.sha256"
if [[ -z "${DATABASE_URL:-}" ]]; then
  INSTALL_REQ="$(mktemp)"
  grep -v '^psycopg2-binary' "$REQ_FILE" > "$INSTALL_REQ"
else
  INSTALL_REQ="$REQ_FILE"
fi

REQ_HASH="$(shasum -a 256 "$INSTALL_REQ" | awk '{print $1}')"
PREV_REQ_HASH="$(cat "$REQ_STAMP" 2>/dev/null || true)"

if [[ "$REQ_HASH" != "$PREV_REQ_HASH" ]]; then
  pip install -r "$INSTALL_REQ"
  printf '%s\n' "$REQ_HASH" > "$REQ_STAMP"
fi

if [[ "${INSTALL_REQ}" != "${REQ_FILE}" ]]; then
  rm -f "$INSTALL_REQ"
fi

TRANSCRIPT_HOST="${TRANSCRIPT_HOST:-127.0.0.1}"
TRANSCRIPT_PORT="${TRANSCRIPT_PORT:-5055}"

uvicorn server.app:app --host "$TRANSCRIPT_HOST" --port "$TRANSCRIPT_PORT"
