"""Database persistence helpers for user, selection, and archive flows."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from typing import Any, Optional

from fastapi import HTTPException
try:
    from sqlalchemy.dialects.postgresql import insert as POSTGRES_INSERT
except Exception:  # pragma: no cover - fallback for non-Postgres builds.
    POSTGRES_INSERT = None
try:
    from sqlalchemy.dialects.sqlite import insert as SQLITE_INSERT
except Exception:  # pragma: no cover - fallback for non-SQLite builds.
    SQLITE_INSERT = None

from .config import (
    ARCHIVE_PLACEHOLDER_CHANNEL_ID,
    ARCHIVE_PLACEHOLDER_CHANNEL_TITLE,
    ARCHIVE_PLACEHOLDER_VIDEO_TITLE,
    CHANNEL_ID_PATTERN,
    MAX_CHANNEL_THUMBNAIL_LENGTH,
    MAX_CHANNEL_TITLE_LENGTH,
    MAX_SELECTION_CHANNELS,
)
from .models import Archive, Channel, User, UserChannel, UserState, Video
from .schemas import SelectionRequest


def _is_postgres_session(session: Any) -> bool:
    dialect_name = getattr(getattr(session, 'bind', None), 'dialect', None)
    return getattr(dialect_name, 'name', '') == 'postgresql'


def _is_sqlite_session(session: Any) -> bool:
    dialect_name = getattr(getattr(session, 'bind', None), 'dialect', None)
    return getattr(dialect_name, 'name', '') == 'sqlite'


def normalize_selection_request(
    req: SelectionRequest,
) -> tuple[dict[str, dict[str, Optional[str]]], list[str]]:
    """Validate and normalize the client selection payload."""
    if len(req.channels) > MAX_SELECTION_CHANNELS:
        raise HTTPException(
            status_code=413,
            detail='too many channels in selection payload',
        )

    selected_ids = {
        channel_id.strip()
        for channel_id in req.selected_ids
        if CHANNEL_ID_PATTERN.fullmatch(channel_id.strip())
    }
    if len(selected_ids) > MAX_SELECTION_CHANNELS:
        raise HTTPException(
            status_code=413,
            detail='too many selected ids in payload',
        )

    normalized_channels: dict[str, dict[str, Optional[str]]] = {}
    for channel in req.channels:
        channel_id = channel.id.strip()
        if not CHANNEL_ID_PATTERN.fullmatch(channel_id):
            continue
        title = channel.title.strip()[:MAX_CHANNEL_TITLE_LENGTH] or channel_id
        thumbnail = (
            (channel.thumbnail_url or '').strip()[:MAX_CHANNEL_THUMBNAIL_LENGTH]
            or None
        )
        normalized_channels[channel_id] = {
            'title': title,
            'thumbnail_url': thumbnail,
        }

    channel_ids = set(normalized_channels.keys())
    if not channel_ids:
        return normalized_channels, []

    normalized_selected_ids = sorted(
        channel_id for channel_id in selected_ids if channel_id in channel_ids
    )
    return normalized_channels, normalized_selected_ids


def ensure_user_exists(session: Any, user_id: str) -> None:
    """Create the user row if it does not exist."""
    if _is_postgres_session(session) and POSTGRES_INSERT is not None:
        stmt = (
            POSTGRES_INSERT(User.__table__)
            .values(id=user_id, plan_tier='free')
            .on_conflict_do_nothing(index_elements=['id'])
        )
        session.execute(stmt)
        return

    if _is_sqlite_session(session) and SQLITE_INSERT is not None:
        stmt = (
            SQLITE_INSERT(User.__table__)
            .values(id=user_id, plan_tier='free')
            .on_conflict_do_nothing(index_elements=['id'])
        )
        session.execute(stmt)
        return

    user = session.query(User).filter(User.id == user_id).first()
    if user is None:
        session.add(User(id=user_id, plan_tier='free'))
        session.flush()


def upsert_user_profile(
    session: Any,
    *,
    user_id: str,
    email: Optional[str],
) -> User:
    """Create or update the user profile row."""
    payload = {
        'id': user_id,
        'email': email,
        'plan_tier': 'free',
    }

    if _is_postgres_session(session) and POSTGRES_INSERT is not None:
        stmt = (
            POSTGRES_INSERT(User.__table__)
            .values(**payload)
            .on_conflict_do_update(
                index_elements=['id'],
                set_={'email': email},
            )
        )
        session.execute(stmt)
        user = session.query(User).filter(User.id == user_id).first()
        if user is None:
            raise HTTPException(status_code=500, detail='user upsert failed')
        return user

    if _is_sqlite_session(session) and SQLITE_INSERT is not None:
        stmt = (
            SQLITE_INSERT(User.__table__)
            .values(**payload)
            .on_conflict_do_update(
                index_elements=['id'],
                set_={'email': email},
            )
        )
        session.execute(stmt)
        user = session.query(User).filter(User.id == user_id).first()
        if user is None:
            raise HTTPException(status_code=500, detail='user upsert failed')
        return user

    user = session.query(User).filter(User.id == user_id).first()
    if user is None:
        user = User(
            id=user_id,
            email=email,
            plan_tier='free',
        )
        session.add(user)
        session.flush()
    else:
        user.email = email
    return user


def upsert_channels(
    session: Any,
    normalized_channels: dict[str, dict[str, Optional[str]]],
) -> None:
    """Upsert the channel metadata set sent by the client."""
    channel_ids = set(normalized_channels.keys())
    if not channel_ids:
        return

    if _is_postgres_session(session) and POSTGRES_INSERT is not None:
        values = [
            {
                'id': channel_id,
                'youtube_channel_id': channel_id,
                'title': payload['title'],
                'thumbnail_url': payload['thumbnail_url'],
            }
            for channel_id, payload in normalized_channels.items()
        ]
        insert_stmt = POSTGRES_INSERT(Channel.__table__).values(values)
        stmt = insert_stmt.on_conflict_do_update(
            index_elements=['id'],
            set_={
                'youtube_channel_id': insert_stmt.excluded.youtube_channel_id,
                'title': insert_stmt.excluded.title,
                'thumbnail_url': insert_stmt.excluded.thumbnail_url,
            },
        )
        session.execute(stmt)
        return

    rows = (
        session.query(Channel)
        .filter(Channel.id.in_(list(channel_ids)))
        .all()
    )
    existing_channels = {row.id: row for row in rows}

    for channel_id, payload in normalized_channels.items():
        existing = existing_channels.get(channel_id)
        if existing is None:
            session.add(
                Channel(
                    id=channel_id,
                    youtube_channel_id=channel_id,
                    title=payload['title'],
                    thumbnail_url=payload['thumbnail_url'],
                )
            )
            continue
        existing.title = payload['title']
        existing.thumbnail_url = payload['thumbnail_url']


def sync_user_channel_links(
    session: Any,
    user_id: str,
    selected_ids_sorted: list[str],
) -> None:
    """Replace the selected channel link set for a user."""
    now = datetime.now(timezone.utc)
    if _is_postgres_session(session) and POSTGRES_INSERT is not None:
        if selected_ids_sorted:
            (
                session.query(UserChannel)
                .filter(
                    UserChannel.user_id == user_id,
                    UserChannel.channel_id.notin_(selected_ids_sorted),
                )
                .delete(synchronize_session=False)
            )
            values = [
                {
                    'user_id': user_id,
                    'channel_id': channel_id,
                    'is_selected': True,
                    'synced_at': now,
                }
                for channel_id in selected_ids_sorted
            ]
            stmt = (
                POSTGRES_INSERT(UserChannel.__table__)
                .values(values)
                .on_conflict_do_update(
                    index_elements=['user_id', 'channel_id'],
                    set_={'is_selected': True, 'synced_at': now},
                )
            )
            session.execute(stmt)
            return

        (
            session.query(UserChannel)
            .filter(UserChannel.user_id == user_id)
            .delete(synchronize_session=False)
        )
        return

    existing_links = (
        session.query(UserChannel).filter(UserChannel.user_id == user_id).all()
    )
    links_by_channel_id = {
        row.channel_id: row for row in existing_links if row.channel_id
    }

    desired = set(selected_ids_sorted)
    for channel_id, row in links_by_channel_id.items():
        if channel_id not in desired:
            session.delete(row)

    for channel_id in selected_ids_sorted:
        existing_link = links_by_channel_id.get(channel_id)
        if existing_link is None:
            session.add(
                UserChannel(
                    user_id=user_id,
                    channel_id=channel_id,
                    is_selected=True,
                    synced_at=now,
                )
            )
            continue
        existing_link.is_selected = True
        existing_link.synced_at = now


def upsert_archive_video(
    session: Any,
    video_id: str,
    metadata: dict[str, Optional[str]],
) -> None:
    """Ensure archive target video/channel records exist and are updated."""
    video = session.query(Video).filter(Video.id == video_id).first()
    channel_id = (
        metadata['channel_id']
        or (video.channel_id if video is not None else None)
        or ARCHIVE_PLACEHOLDER_CHANNEL_ID
    )
    channel = session.query(Channel).filter(Channel.id == channel_id).first()
    if channel is None:
        session.add(
            Channel(
                id=channel_id,
                youtube_channel_id=channel_id,
                title=metadata['channel_title']
                or ARCHIVE_PLACEHOLDER_CHANNEL_TITLE,
                thumbnail_url=metadata['channel_thumbnail_url'],
            )
        )
        session.flush()
    else:
        if metadata['channel_title'] is not None:
            channel.title = metadata['channel_title']
        elif not channel.title:
            channel.title = ARCHIVE_PLACEHOLDER_CHANNEL_TITLE
        if metadata['channel_thumbnail_url'] is not None:
            channel.thumbnail_url = metadata['channel_thumbnail_url']

    if video is None:
        session.add(
            Video(
                id=video_id,
                youtube_id=video_id[:32],
                channel_id=channel_id,
                title=metadata['title'] or ARCHIVE_PLACEHOLDER_VIDEO_TITLE,
                thumbnail_url=metadata['thumbnail_url'],
                published_at=None,
            )
        )
        session.flush()
        return

    video.channel_id = channel_id
    if metadata['title'] is not None:
        video.title = metadata['title']
    elif not video.title:
        video.title = ARCHIVE_PLACEHOLDER_VIDEO_TITLE
    if metadata['thumbnail_url'] is not None:
        video.thumbnail_url = metadata['thumbnail_url']


def serialize_archive_items(
    session: Any,
    archives: list[Archive],
) -> list[dict[str, Any]]:
    """Load related video/channel metadata for archive responses."""
    if not archives:
        return []

    video_ids = [item.video_id for item in archives]
    videos = session.query(Video).filter(Video.id.in_(video_ids)).all()
    videos_by_id = {video.id: video for video in videos}
    channel_ids = {video.channel_id for video in videos if video.channel_id}
    channels = (
        session.query(Channel).filter(Channel.id.in_(list(channel_ids))).all()
        if channel_ids
        else []
    )
    channels_by_id = {channel.id: channel for channel in channels}

    items = []
    for archived in archives:
        video = videos_by_id.get(archived.video_id)
        channel = channels_by_id.get(video.channel_id) if video else None
        items.append(
            {
                'video_id': archived.video_id,
                'archived_at': int(archived.archived_at.timestamp() * 1000),
                'title': (
                    video.title
                    if video
                    else ARCHIVE_PLACEHOLDER_VIDEO_TITLE
                ),
                'thumbnail_url': video.thumbnail_url if video else None,
                'channel_id': (
                    video.channel_id
                    if video
                    else ARCHIVE_PLACEHOLDER_CHANNEL_ID
                ),
                'channel_title': (
                    channel.title
                    if channel
                    else ARCHIVE_PLACEHOLDER_CHANNEL_TITLE
                ),
                'channel_thumbnail_url': (
                    channel.thumbnail_url if channel else None
                ),
            }
        )
    return items


def upsert_user_state_row(
    session: Any,
    user_id: str,
    *,
    selection_change_day: int,
    selection_changes_today: int,
    opened_video_ids: list[str],
) -> None:
    """Upsert the per-user synchronized app state row."""
    now = datetime.now(timezone.utc)
    encoded_opened_video_ids = json.dumps(opened_video_ids)
    payload = {
        'user_id': user_id,
        'selection_change_day': selection_change_day,
        'selection_changes_today': selection_changes_today,
        'opened_video_ids': encoded_opened_video_ids,
        'updated_at': now,
    }

    if _is_postgres_session(session) and POSTGRES_INSERT is not None:
        stmt = (
            POSTGRES_INSERT(UserState.__table__)
            .values(**payload)
            .on_conflict_do_update(
                index_elements=['user_id'],
                set_={
                    'selection_change_day': selection_change_day,
                    'selection_changes_today': selection_changes_today,
                    'opened_video_ids': encoded_opened_video_ids,
                    'updated_at': now,
                },
            )
        )
        session.execute(stmt)
        return

    if _is_sqlite_session(session) and SQLITE_INSERT is not None:
        stmt = (
            SQLITE_INSERT(UserState.__table__)
            .values(**payload)
            .on_conflict_do_update(
                index_elements=['user_id'],
                set_={
                    'selection_change_day': selection_change_day,
                    'selection_changes_today': selection_changes_today,
                    'opened_video_ids': encoded_opened_video_ids,
                    'updated_at': now,
                },
            )
        )
        session.execute(stmt)
        return

    state = (
        session.query(UserState)
        .filter(UserState.user_id == user_id)
        .first()
    )
    if state is None:
        state = UserState(user_id=user_id)

    state.selection_change_day = selection_change_day
    state.selection_changes_today = selection_changes_today
    state.opened_video_ids = encoded_opened_video_ids
    state.updated_at = now
    session.add(state)
