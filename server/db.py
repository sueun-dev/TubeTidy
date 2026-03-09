"""Database helpers for SQLAlchemy sessions and health checks."""

from contextlib import contextmanager
import logging
import os
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import SQLAlchemyError

from . import models

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env')

DATABASE_URL = os.getenv('DATABASE_URL')

_ENGINE = None
_SESSION_LOCAL = None

if DATABASE_URL:
    _ENGINE = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,
    )
    _SESSION_LOCAL = sessionmaker(
        bind=_ENGINE, autoflush=False, autocommit=False
    )


def is_db_enabled() -> bool:
    """Return True when DATABASE_URL is configured."""
    return _ENGINE is not None


def init_db() -> None:
    """Initialize database schema if enabled."""
    if _ENGINE is None:
        return
    try:
        models.Base.metadata.create_all(_ENGINE)
    except SQLAlchemyError:
        logging.exception('Failed to initialize database schema.')
        raise


def migrate_db() -> None:
    """Apply explicit schema/data migrations for existing databases."""
    if _ENGINE is None:
        return
    init_db()
    _apply_runtime_migrations()


def check_db() -> bool:
    """Check database connectivity."""
    if _ENGINE is None:
        return False
    try:
        with _ENGINE.connect() as conn:
            conn.execute(text('SELECT 1'))
        return True
    except SQLAlchemyError:
        return False


def _apply_runtime_migrations() -> None:
    """Apply lightweight runtime migrations for existing schemas."""
    if _ENGINE is None:
        return

    dialect = _ENGINE.dialect.name
    if dialect == 'postgresql':
        statements = (
            """
            DELETE FROM user_channels a
            USING user_channels b
            WHERE a.id < b.id
              AND a.user_id = b.user_id
              AND a.channel_id = b.channel_id
            """,
            """
            DELETE FROM archives a
            USING archives b
            WHERE a.id < b.id
              AND a.user_id = b.user_id
              AND a.video_id = b.video_id
            """,
            """
            CREATE UNIQUE INDEX IF NOT EXISTS uq_user_channels_user_channel
            ON user_channels (user_id, channel_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS ix_user_channels_user_selected
            ON user_channels (user_id, is_selected)
            """,
            """
            CREATE UNIQUE INDEX IF NOT EXISTS uq_archives_user_video
            ON archives (user_id, video_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS ix_archives_user_archived_at
            ON archives (user_id, archived_at DESC)
            """,
        )
    elif dialect == 'sqlite':
        statements = (
            """
            DELETE FROM user_channels
            WHERE rowid NOT IN (
              SELECT MAX(rowid)
              FROM user_channels
              GROUP BY user_id, channel_id
            )
            """,
            """
            DELETE FROM archives
            WHERE rowid NOT IN (
              SELECT MAX(rowid)
              FROM archives
              GROUP BY user_id, video_id
            )
            """,
            """
            CREATE UNIQUE INDEX IF NOT EXISTS uq_user_channels_user_channel
            ON user_channels (user_id, channel_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS ix_user_channels_user_selected
            ON user_channels (user_id, is_selected)
            """,
            """
            CREATE UNIQUE INDEX IF NOT EXISTS uq_archives_user_video
            ON archives (user_id, video_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS ix_archives_user_archived_at
            ON archives (user_id, archived_at)
            """,
        )
    else:
        return

    try:
        with _ENGINE.begin() as conn:
            for statement in statements:
                conn.execute(text(statement))
            _ensure_optional_columns(conn)
    except SQLAlchemyError:
        logging.exception('Runtime migration failed.')
        raise


def _ensure_optional_columns(conn) -> None:
    """Add columns introduced after initial release when they are missing."""
    inspector = inspect(conn)
    table_columns = {
        table_name: {
            column['name']
            for column in inspector.get_columns(table_name)
        }
        for table_name in inspector.get_table_names()
    }

    if (
        'videos' in table_columns
        and 'thumbnail_url' not in table_columns['videos']
    ):
        conn.execute(text('ALTER TABLE videos ADD COLUMN thumbnail_url TEXT'))


def validate_schema() -> tuple[bool, Optional[str]]:
    """Validate that the live database has the required application schema."""
    if _ENGINE is None:
        return True, None

    required_tables = {
        'users',
        'user_state',
        'channels',
        'user_channels',
        'videos',
        'archives',
        'transcript_cache',
    }
    required_columns = {
        'videos': {'thumbnail_url'},
    }

    try:
        with _ENGINE.connect() as conn:
            inspector = inspect(conn)
            tables = set(inspector.get_table_names())
            missing_tables = sorted(required_tables - tables)
            if missing_tables:
                return False, f"missing tables: {', '.join(missing_tables)}"

            for table_name, columns in required_columns.items():
                table_columns = {
                    column['name']
                    for column in inspector.get_columns(table_name)
                }
                missing_columns = sorted(columns - table_columns)
                if missing_columns:
                    return (
                        False,
                        (
                            f'{table_name} missing columns: '
                            f"{', '.join(missing_columns)}"
                        ),
                    )
    except SQLAlchemyError as exc:
        return False, f'schema inspection failed: {exc.__class__.__name__}'

    return True, None


@contextmanager
def get_session():
    """Yield a SQLAlchemy session or None if DB disabled."""
    if _ENGINE is None or _SESSION_LOCAL is None:
        yield None
        return
    session = _SESSION_LOCAL()
    try:
        yield session
    finally:
        session.close()
