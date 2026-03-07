#!/usr/bin/env python3
"""Apply explicit database migrations before starting the API server."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from server.db import check_db, is_db_enabled, migrate_db, validate_schema


def main() -> int:
    if not is_db_enabled():
        print('DATABASE_URL is not set. Nothing to migrate.')
        return 0

    if not check_db():
        print('Database is not reachable. Migration aborted.', file=sys.stderr)
        return 1

    migrate_db()
    schema_ok, schema_detail = validate_schema()
    if not schema_ok:
        detail = schema_detail or 'unknown schema error'
        print(f'Database schema validation failed: {detail}', file=sys.stderr)
        return 1

    print('Database migration complete.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
