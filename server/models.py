"""SQLAlchemy ORM models for the YouTube Summary backend."""

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from .db_base import Base


class User(Base):
    """User profile record."""
    __tablename__ = 'users'

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    plan_tier: Mapped[str] = mapped_column(String(32), default='free')
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class Channel(Base):
    """YouTube channel metadata."""
    __tablename__ = 'channels'

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    youtube_channel_id: Mapped[str] = mapped_column(String(64), index=True)
    title: Mapped[str] = mapped_column(String(255))
    thumbnail_url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class UserChannel(Base):
    """Channel selection mapping for users."""
    __tablename__ = 'user_channels'
    __table_args__ = (
        UniqueConstraint('user_id', 'channel_id', name='uq_user_channels_user_channel'),
        Index('ix_user_channels_user_selected', 'user_id', 'is_selected'),
    )

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey('users.id'))
    channel_id: Mapped[str] = mapped_column(
        String(64), ForeignKey('channels.id')
    )
    is_selected: Mapped[bool] = mapped_column(Boolean, default=False)
    synced_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class Video(Base):
    """Video metadata record."""
    __tablename__ = 'videos'

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    youtube_id: Mapped[str] = mapped_column(String(32), index=True)
    channel_id: Mapped[str] = mapped_column(
        String(64), ForeignKey('channels.id')
    )
    title: Mapped[str] = mapped_column(String(255))
    published_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class Archive(Base):
    """Archived video reference."""
    __tablename__ = 'archives'
    __table_args__ = (
        UniqueConstraint('user_id', 'video_id', name='uq_archives_user_video'),
        Index('ix_archives_user_archived_at', 'user_id', 'archived_at'),
    )

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey('users.id'))
    video_id: Mapped[str] = mapped_column(String(64), ForeignKey('videos.id'))
    archived_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class TranscriptCache(Base):
    """Cached transcript entries."""
    __tablename__ = 'transcript_cache'

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    video_id: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    text: Mapped[str] = mapped_column(Text)
    summary: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(String(32), default='captions')
    partial: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
