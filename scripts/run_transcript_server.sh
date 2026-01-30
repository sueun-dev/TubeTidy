#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

python3 -m venv "$ROOT_DIR/.venv"
source "$ROOT_DIR/.venv/bin/activate"

pip install -r "$ROOT_DIR/server/requirements.txt"
pip install --upgrade yt-dlp

TRANSCRIPT_HOST="${TRANSCRIPT_HOST:-127.0.0.1}"
TRANSCRIPT_PORT="${TRANSCRIPT_PORT:-5055}"

uvicorn server.app:app --host "$TRANSCRIPT_HOST" --port "$TRANSCRIPT_PORT"
