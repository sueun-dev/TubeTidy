"""FastAPI request payload schemas."""

from typing import Optional

from pydantic import BaseModel, Field


class TranscriptRequest(BaseModel):
    """Payload for transcript and summary requests."""

    video_id: str
    max_chars: Optional[int] = 1200
    summarize: Optional[bool] = True
    summary_lines: Optional[int] = 3


class ArchiveToggleRequest(BaseModel):
    """Payload for toggling an archive entry."""

    user_id: str
    video_id: str
    archived: Optional[bool] = None
    title: Optional[str] = None
    thumbnail_url: Optional[str] = None
    channel_id: Optional[str] = None
    channel_title: Optional[str] = None
    channel_thumbnail_url: Optional[str] = None


class ArchiveClearRequest(BaseModel):
    """Payload for clearing all archive entries for a user."""

    user_id: str


class UserUpsertRequest(BaseModel):
    """Payload for creating or updating a user profile."""

    user_id: str
    email: Optional[str] = None
    plan_tier: Optional[str] = None


class UserPlanRequest(BaseModel):
    """Payload for updating a user's plan tier."""

    user_id: str
    plan_tier: str


class UserStateUpsertRequest(BaseModel):
    """Payload for upserting per-user app state."""

    user_id: str
    selection_change_day: Optional[int] = 0
    selection_changes_today: Optional[int] = 0
    opened_video_ids: list[str] = Field(default_factory=list)


class ChannelPayload(BaseModel):
    """Channel metadata for selection sync."""

    id: str
    title: str
    thumbnail_url: Optional[str] = None


class SelectionRequest(BaseModel):
    """Payload for saving selected channels."""

    user_id: str
    channels: list[ChannelPayload]
    selected_ids: list[str]
