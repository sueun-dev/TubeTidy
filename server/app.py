"""FastAPI backend for YouTube Summary."""

from collections import deque
from contextlib import asynccontextmanager, contextmanager
import html
import json
import os
import re
import shutil
import tempfile
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import requests
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError

from .db import check_db, get_session, init_db, is_db_enabled
from .models import (
    Archive,
    Channel,
    TranscriptCache,
    User,
    UserChannel,
    UserState,
    Video,
)

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env')

OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
OPENAI_SUMMARY_MODEL = os.getenv('OPENAI_SUMMARY_MODEL', 'gpt-4o-mini')
OPENAI_SUMMARY_INPUT_CHARS = int(
    os.getenv('OPENAI_SUMMARY_INPUT_CHARS', '4000')
)
OPENAI_SUMMARY_MAX_TOKENS = int(os.getenv('OPENAI_SUMMARY_MAX_TOKENS', '200'))
YTDLP_COOKIES_PATH = os.getenv('YTDLP_COOKIES_PATH')
YTDLP_COOKIES_FROM_BROWSER = os.getenv('YTDLP_COOKIES_FROM_BROWSER')
YTDLP_PLAYER_CLIENTS = os.getenv(
    'YTDLP_PLAYER_CLIENTS',
    'android,web,ios,tv,web_embedded',
)
TRANSCRIPT_CACHE_TTL = int(os.getenv('TRANSCRIPT_CACHE_TTL', '86400'))
TRANSCRIPT_MAX_CONCURRENCY = int(os.getenv('TRANSCRIPT_MAX_CONCURRENCY', '2'))
TRANSCRIPT_QUEUE_TIMEOUT = int(os.getenv('TRANSCRIPT_QUEUE_TIMEOUT', '20'))
TRANSCRIPT_RATE_LIMIT_PER_WINDOW = int(
    os.getenv('TRANSCRIPT_RATE_LIMIT_PER_WINDOW', '45')
)
TRANSCRIPT_RATE_LIMIT_WINDOW_SECONDS = int(
    os.getenv('TRANSCRIPT_RATE_LIMIT_WINDOW_SECONDS', '60')
)
USER_AGENT = os.getenv(
    'YTDLP_USER_AGENT',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
)

_cors_env = os.getenv(
    'CORS_ALLOWED_ORIGINS',
    (
        'http://localhost:5201,http://127.0.0.1:5201,'
        'http://localhost:5301,http://127.0.0.1:5301'
    ),
)
ALLOWED_ORIGINS = tuple(
    origin.strip()
    for origin in _cors_env.split(',')
    if origin.strip()
)
ALLOW_CREDENTIALS = '*' not in ALLOWED_ORIGINS
BACKEND_REQUIRE_AUTH = os.getenv(
    'BACKEND_REQUIRE_AUTH', 'true'
).strip().lower() not in {'0', 'false', 'no'}
ENABLE_API_DOCS = os.getenv(
    'ENABLE_API_DOCS', 'false'
).strip().lower() in {'1', 'true', 'yes'}
AUTH_CLOCK_SKEW_SECONDS = int(os.getenv('AUTH_CLOCK_SKEW_SECONDS', '120'))
GOOGLE_TOKENINFO_URL = os.getenv(
    'GOOGLE_TOKENINFO_URL',
    'https://oauth2.googleapis.com/tokeninfo',
)
GOOGLE_TOKENINFO_TIMEOUT_SECONDS = float(
    os.getenv('GOOGLE_TOKENINFO_TIMEOUT_SECONDS', '5')
)
_configured_client_ids = {
    value.strip()
    for value in (
        os.getenv('GOOGLE_CLIENT_IDS', '').split(',')
        + [
            os.getenv('GOOGLE_WEB_CLIENT_ID', ''),
            os.getenv('GOOGLE_IOS_CLIENT_ID', ''),
        ]
    )
    if value and value.strip()
}

CACHE_DIR = ROOT / 'server' / 'cache'
CACHE_DIR.mkdir(parents=True, exist_ok=True)
TRANSCRIPT_SEMAPHORE = threading.Semaphore(max(1, TRANSCRIPT_MAX_CONCURRENCY))
DEFAULT_HEADERS = {'User-Agent': USER_AGENT}
VIDEO_ID_PATTERN = re.compile(r'^[A-Za-z0-9_-]{6,32}$')
ARCHIVE_VIDEO_ID_PATTERN = re.compile(r'^[A-Za-z0-9_-]{6,64}$')
USER_ID_PATTERN = re.compile(r'^[A-Za-z0-9._:-]{3,128}$')
CHANNEL_ID_PATTERN = re.compile(r'^[A-Za-z0-9_-]{3,64}$')
PLAN_TIER_PATTERN = re.compile(r'^(free|starter|growth|unlimited|lifetime)$')
MAX_SELECTION_CHANNELS = int(os.getenv('MAX_SELECTION_CHANNELS', '200'))
MAX_CHANNEL_TITLE_LENGTH = 255
MAX_CHANNEL_THUMBNAIL_LENGTH = 2048
MAX_OPENED_VIDEO_IDS = int(os.getenv('MAX_OPENED_VIDEO_IDS', '500'))
MAX_SELECTION_CHANGE_DAY = 99991231
MAX_SELECTION_CHANGES_TODAY = 31
ARCHIVE_PLACEHOLDER_CHANNEL_ID = '__archive_channel__'
ARCHIVE_PLACEHOLDER_CHANNEL_TITLE = 'Archived videos'
ARCHIVE_PLACEHOLDER_VIDEO_TITLE = 'Archived video'
TRANSCRIPT_DEFAULT_MAX_CHARS = 1200
TRANSCRIPT_MIN_MAX_CHARS = 300
TRANSCRIPT_MAX_MAX_CHARS = 10000
AUTH_CACHE_MAX_ITEMS = int(os.getenv('AUTH_CACHE_MAX_ITEMS', '1024'))
AUTH_CACHE_LOCK = threading.Lock()
AUTH_CACHE: dict[str, tuple[float, str]] = {}
TRANSCRIPT_RATE_LOCK = threading.Lock()
TRANSCRIPT_RATE_BUCKETS: dict[str, deque[float]] = {}


@asynccontextmanager
async def app_lifespan(_: FastAPI):
    """Startup and shutdown lifecycle hooks."""
    if BACKEND_REQUIRE_AUTH and not _configured_client_ids:
        raise RuntimeError(
            'BACKEND_REQUIRE_AUTH=true 이지만 '
            'GOOGLE_CLIENT_IDS/GOOGLE_WEB_CLIENT_ID/GOOGLE_IOS_CLIENT_ID가 '
            '설정되지 않았습니다.'
        )
    init_db()
    yield


app = FastAPI(
    lifespan=app_lifespan,
    docs_url='/docs' if ENABLE_API_DOCS else None,
    redoc_url='/redoc' if ENABLE_API_DOCS else None,
    openapi_url='/openapi.json' if ENABLE_API_DOCS else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=list(ALLOWED_ORIGINS),
    allow_credentials=ALLOW_CREDENTIALS,
    allow_methods=['*'],
    allow_headers=['*'],
)


@app.middleware('http')
async def apply_security_headers(request: Request, call_next):
    """Apply basic security headers and correlation id."""
    response = await call_next(request)
    request_id = request.headers.get('X-Request-Id') or str(uuid.uuid4())
    response.headers.setdefault('X-Request-Id', request_id)
    response.headers.setdefault('X-Content-Type-Options', 'nosniff')
    response.headers.setdefault('X-Frame-Options', 'DENY')
    response.headers.setdefault('Referrer-Policy', 'no-referrer')
    response.headers.setdefault(
        'Content-Security-Policy',
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
    )
    response.headers.setdefault(
        'Permissions-Policy',
        'geolocation=(), microphone=(), camera=()',
    )
    response.headers.setdefault('Cross-Origin-Resource-Policy', 'same-site')
    response.headers.setdefault('Cache-Control', 'no-store')
    if request.url.scheme == 'https':
        response.headers.setdefault(
            'Strict-Transport-Security',
            'max-age=31536000; includeSubDomains',
        )
    return response


@contextmanager
def _transcript_slot(timeout: int):
    """Acquire a transcript slot or raise if the queue is full."""
    if not TRANSCRIPT_SEMAPHORE.acquire(timeout=timeout):
        raise HTTPException(
            status_code=429,
            detail='요청이 많아 잠시 후 다시 시도해주세요.',
        )
    try:
        yield
    finally:
        TRANSCRIPT_SEMAPHORE.release()

def _sanitize_user_id(raw_user_id: str) -> str:
    user_id = raw_user_id.strip()
    if not user_id:
        raise HTTPException(status_code=400, detail='user_id is required')
    if not USER_ID_PATTERN.fullmatch(user_id):
        raise HTTPException(status_code=400, detail='user_id is invalid')
    return user_id


def _sanitize_video_id(raw_video_id: str) -> str:
    video_id = raw_video_id.strip()
    if not video_id:
        raise HTTPException(status_code=400, detail='video_id is required')
    if not VIDEO_ID_PATTERN.fullmatch(video_id):
        raise HTTPException(status_code=400, detail='video_id is invalid')
    return video_id


def _sanitize_archive_video_id(raw_video_id: str) -> str:
    video_id = raw_video_id.strip()
    if not video_id:
        raise HTTPException(status_code=400, detail='video_id is required')
    if not ARCHIVE_VIDEO_ID_PATTERN.fullmatch(video_id):
        raise HTTPException(status_code=400, detail='video_id is invalid')
    return video_id


def _sanitize_plan_tier(raw_plan_tier: str) -> str:
    plan_tier = raw_plan_tier.strip().lower()
    if not plan_tier:
        raise HTTPException(
            status_code=400,
            detail='user_id and plan_tier are required',
        )
    if not PLAN_TIER_PATTERN.fullmatch(plan_tier):
        raise HTTPException(status_code=400, detail='plan_tier is invalid')
    return plan_tier


def _sanitize_selection_change_day(raw_day: Optional[int]) -> int:
    if raw_day is None:
        return 0
    value = int(raw_day)
    if value < 0:
        return 0
    if value > MAX_SELECTION_CHANGE_DAY:
        return MAX_SELECTION_CHANGE_DAY
    return value


def _sanitize_selection_changes_today(raw_count: Optional[int]) -> int:
    if raw_count is None:
        return 0
    value = int(raw_count)
    if value < 0:
        return 0
    if value > MAX_SELECTION_CHANGES_TODAY:
        return MAX_SELECTION_CHANGES_TODAY
    return value


def _normalize_opened_video_ids(raw_ids: list[str]) -> list[str]:
    normalized = []
    seen = set()
    for raw in raw_ids:
        video_id = raw.strip()
        if not VIDEO_ID_PATTERN.fullmatch(video_id):
            continue
        if video_id in seen:
            continue
        seen.add(video_id)
        normalized.append(video_id)
        if len(normalized) >= MAX_OPENED_VIDEO_IDS:
            break
    return normalized


def _sanitize_email(raw_email: Optional[str]) -> Optional[str]:
    if raw_email is None:
        return None
    email = raw_email.strip()
    if not email:
        return None
    if len(email) > 255:
        raise HTTPException(status_code=400, detail='email is too long')
    if '@' not in email:
        raise HTTPException(status_code=400, detail='email is invalid')
    return email


def _extract_bearer_token(authorization: Optional[str]) -> str:
    if not authorization:
        raise HTTPException(status_code=401, detail='authorization is required')
    scheme, _, token = authorization.partition(' ')
    if scheme.lower() != 'bearer' or not token.strip():
        raise HTTPException(status_code=401, detail='invalid authorization')
    return token.strip()


def _verify_google_user(token: str) -> str:
    now = time.time()
    with AUTH_CACHE_LOCK:
        cached = AUTH_CACHE.get(token)
        if cached and cached[0] > now:
            return cached[1]

    try:
        response = requests.get(
            GOOGLE_TOKENINFO_URL,
            params={'id_token': token},
            timeout=GOOGLE_TOKENINFO_TIMEOUT_SECONDS,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=401, detail='invalid access token') from exc

    if response.status_code != 200:
        raise HTTPException(status_code=401, detail='invalid access token')

    try:
        payload = response.json()
    except ValueError as exc:
        raise HTTPException(status_code=401, detail='invalid access token') from exc

    audience = payload.get('aud')
    if _configured_client_ids and audience not in _configured_client_ids:
        raise HTTPException(status_code=401, detail='token audience mismatch')

    issuer = payload.get('iss')
    if issuer not in (
        'accounts.google.com',
        'https://accounts.google.com',
    ):
        raise HTTPException(status_code=401, detail='token issuer mismatch')

    subject = payload.get('sub')
    if not isinstance(subject, str) or not USER_ID_PATTERN.fullmatch(subject):
        raise HTTPException(status_code=401, detail='invalid token subject')

    expires_at = payload.get('exp')
    if not expires_at:
        raise HTTPException(status_code=401, detail='token exp missing')
    try:
        expiry = float(expires_at)
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=401, detail='token exp invalid') from exc
    if expiry <= now - AUTH_CLOCK_SKEW_SECONDS:
        raise HTTPException(status_code=401, detail='token expired')

    with AUTH_CACHE_LOCK:
        AUTH_CACHE[token] = (expiry, subject)
        if len(AUTH_CACHE) > AUTH_CACHE_MAX_ITEMS:
            AUTH_CACHE.pop(next(iter(AUTH_CACHE)))
    return subject


def _authorize_user(user_id: str, authorization: Optional[str]) -> str:
    normalized_user_id = _sanitize_user_id(user_id)
    if not BACKEND_REQUIRE_AUTH:
        return normalized_user_id
    token = _extract_bearer_token(authorization)
    token_subject = _verify_google_user(token)
    if token_subject != normalized_user_id:
        raise HTTPException(status_code=403, detail='user mismatch')
    return normalized_user_id


def _resolve_client_id(request: Request) -> str:
    forwarded = request.headers.get('x-forwarded-for', '')
    if forwarded:
        candidate = forwarded.split(',')[0].strip()
        if candidate:
            return candidate[:128]
    client = request.client.host if request.client else 'unknown'
    return (client or 'unknown')[:128]


def _enforce_transcript_rate_limit(client_id: str) -> None:
    if TRANSCRIPT_RATE_LIMIT_PER_WINDOW <= 0:
        return
    now = time.monotonic()
    cutoff = now - max(1, TRANSCRIPT_RATE_LIMIT_WINDOW_SECONDS)
    with TRANSCRIPT_RATE_LOCK:
        bucket = TRANSCRIPT_RATE_BUCKETS.setdefault(client_id, deque())
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= TRANSCRIPT_RATE_LIMIT_PER_WINDOW:
            raise HTTPException(
                status_code=429,
                detail='요청이 많아 잠시 후 다시 시도해주세요.',
            )
        bucket.append(now)
        if len(TRANSCRIPT_RATE_BUCKETS) > 8192:
            stale = [
                key for key, values in TRANSCRIPT_RATE_BUCKETS.items() if not values
            ]
            for key in stale:
                TRANSCRIPT_RATE_BUCKETS.pop(key, None)


@app.get('/')
def root():
    """Return basic service metadata."""
    return {
        'name': 'YouTube Summary API',
        'version': '1.0.0',
        'docs': '/docs',
    }


@app.get('/health')
def health_check():
    """Return health status and database connectivity."""
    db_enabled = is_db_enabled()
    return {
        'status': 'ok',
        'db_enabled': db_enabled,
        'db_ok': check_db() if db_enabled else False,
    }


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


@app.post('/transcript')
def transcript(req: TranscriptRequest, request: Request):
    """Return transcript and summary for a YouTube video."""
    _enforce_transcript_rate_limit(_resolve_client_id(request))
    video_id = _sanitize_video_id(req.video_id)
    max_chars = _sanitize_max_chars(req.max_chars)

    cached = load_cache(video_id)
    if cached:
        return {**cached, 'cached': True}

    with _transcript_slot(TRANSCRIPT_QUEUE_TIMEOUT):
        caption_text = fetch_caption_text(video_id)
        if not caption_text:
            caption_text = fetch_caption_text_via_ytdlp(video_id)

        if caption_text:
            text, partial = trim_text(caption_text, max_chars)
            summary = (
                build_summary(caption_text, req.summary_lines)
                if req.summarize
                else None
            )
            payload = {
                'text': text,
                'summary': summary,
                'source': 'captions',
                'partial': partial,
            }
            save_cache(video_id, payload)
            return {**payload, 'cached': False}

        if not OPENAI_API_KEY:
            raise HTTPException(
                status_code=400,
                detail='OPENAI_API_KEY가 설정되어 있지 않습니다.',
            )

        audio_path, error = download_audio(video_id)
        if audio_path is None:
            detail = '음성 다운로드에 실패했습니다.'
            if error:
                if is_membership_error(error):
                    detail = 'You might not have membership for this video.'
                elif 'HTTP Error 403' in error or 'Forbidden' in error:
                    detail = (
                        '음성 다운로드가 차단되었습니다. '
                        'YouTube 제한(로그인/연령/지역) 또는 다운로더 업데이트가 필요합니다.'
                    )
            raise HTTPException(status_code=500, detail=detail)

        try:
            transcript_text = transcribe_audio(audio_path)
        finally:
            try:
                os.remove(audio_path)
            except OSError:
                pass

        if not transcript_text:
            raise HTTPException(status_code=500, detail='음성 인식에 실패했습니다.')

        text, partial = trim_text(transcript_text, max_chars)
        summary = (
            build_summary(transcript_text, req.summary_lines)
            if req.summarize
            else None
        )
        payload = {
            'text': text,
            'summary': summary,
            'source': 'whisper',
            'partial': partial,
        }
        save_cache(video_id, payload)
        return {**payload, 'cached': False}


@app.get('/archives')
def list_archives(
    user_id: str,
    authorization: Optional[str] = Header(default=None),
):
    """List archived videos for a user."""
    user_id = _authorize_user(user_id, authorization)
    if is_db_enabled():
        try:
            with get_session() as session:
                if session is None:
                    return {'items': []}
                items = (
                    session.query(Archive)
                    .filter(Archive.user_id == user_id)
                    .order_by(Archive.archived_at.desc())
                    .all()
                )
                return {
                    'items': [
                        {
                            'video_id': item.video_id,
                            'archived_at': int(
                                item.archived_at.timestamp() * 1000
                            ),
                        }
                        for item in items
                    ]
                }
        except SQLAlchemyError:
            return {'items': []}
    return {'items': _load_archives_file(user_id)}


@app.post('/archives/toggle')
def toggle_archive(
    req: ArchiveToggleRequest,
    authorization: Optional[str] = Header(default=None),
):
    """Toggle archive status for a video."""
    user_id = _authorize_user(req.user_id, authorization)
    video_id = _sanitize_archive_video_id(req.video_id)

    if is_db_enabled():
        try:
            with get_session() as session:
                if session is None:
                    raise HTTPException(
                        status_code=500,
                        detail='database not available',
                    )
                user = session.query(User).filter(User.id == user_id).first()
                if user is None:
                    session.add(User(id=user_id, plan_tier='free'))
                    session.flush()
                existing = (
                    session.query(Archive)
                    .filter(
                        Archive.user_id == user_id,
                        Archive.video_id == video_id,
                    )
                    .first()
                )
                if existing:
                    session.delete(existing)
                    session.commit()
                    return {'archived': False}
                _ensure_archive_video(session, video_id)
                archived = Archive(user_id=user_id, video_id=video_id)
                session.add(archived)
                session.commit()
                return {
                    'archived': True,
                    'archived_at': int(archived.archived_at.timestamp() * 1000),
                }
        except IntegrityError as exc:
            raise HTTPException(
                status_code=409, detail='archive conflict'
            ) from exc
        except SQLAlchemyError as exc:
            raise HTTPException(
                status_code=500, detail='archive update failed'
            ) from exc

    return _toggle_archive_file(user_id, video_id)


@app.post('/archives/clear')
def clear_archives(
    req: ArchiveClearRequest,
    authorization: Optional[str] = Header(default=None),
):
    """Clear all archive entries for a user."""
    user_id = _authorize_user(req.user_id, authorization)

    if is_db_enabled():
        try:
            with get_session() as session:
                if session is None:
                    raise HTTPException(
                        status_code=500,
                        detail='database not available',
                    )
                session.query(Archive).filter(
                    Archive.user_id == user_id
                ).delete()
                session.commit()
                return {'cleared': True}
        except SQLAlchemyError as exc:
            raise HTTPException(
                status_code=500, detail='archive clear failed'
            ) from exc

    _save_archives_file(user_id, [])
    return {'cleared': True}


@app.post('/user/upsert')
def upsert_user(
    req: UserUpsertRequest,
    authorization: Optional[str] = Header(default=None),
):
    """Create or update a user profile."""
    user_id = _authorize_user(req.user_id, authorization)
    email = _sanitize_email(req.email)
    plan_tier = _sanitize_plan_tier(req.plan_tier) if req.plan_tier else None
    if not is_db_enabled():
        return {
            'user_id': user_id,
            'email': email,
            'plan_tier': plan_tier or 'free',
        }
    try:
        with get_session() as session:
            if session is None:
                raise HTTPException(
                    status_code=500,
                    detail='database not available',
                )
            user = session.query(User).filter(User.id == user_id).first()
            if user is None:
                user = User(
                    id=user_id,
                    email=email,
                    plan_tier=plan_tier or 'free',
                )
                session.add(user)
            else:
                user.email = email
                if plan_tier is not None:
                    user.plan_tier = plan_tier
            session.commit()
            return {
                'user_id': user.id,
                'email': user.email,
                'plan_tier': user.plan_tier,
            }
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=500, detail='user upsert failed'
        ) from exc


@app.get('/user')
def get_user(
    user_id: str,
    authorization: Optional[str] = Header(default=None),
):
    """Fetch a user profile."""
    user_id = _authorize_user(user_id, authorization)
    if not is_db_enabled():
        return {'user_id': user_id, 'plan_tier': 'free'}
    try:
        with get_session() as session:
            if session is None:
                raise HTTPException(
                    status_code=500,
                    detail='database not available',
                )
            user = session.query(User).filter(User.id == user_id).first()
            if user is None:
                raise HTTPException(status_code=404, detail='user not found')
            return {
                'user_id': user.id,
                'email': user.email,
                'plan_tier': user.plan_tier,
            }
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=500, detail='user fetch failed'
        ) from exc


@app.post('/user/plan')
def update_user_plan(
    req: UserPlanRequest,
    authorization: Optional[str] = Header(default=None),
):
    """Update or create the user's plan tier."""
    user_id = _authorize_user(req.user_id, authorization)
    plan_tier = _sanitize_plan_tier(req.plan_tier)
    if not is_db_enabled():
        return {'updated': True, 'plan_tier': plan_tier}
    try:
        with get_session() as session:
            if session is None:
                raise HTTPException(
                    status_code=500,
                    detail='database not available',
                )
            user = session.query(User).filter(User.id == user_id).first()
            if user is None:
                user = User(id=user_id, plan_tier=plan_tier)
                session.add(user)
            else:
                user.plan_tier = plan_tier
            session.commit()
            return {'updated': True, 'plan_tier': user.plan_tier}
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=500, detail='plan update failed'
        ) from exc


@app.get('/user/state')
def get_user_state(
    user_id: str,
    authorization: Optional[str] = Header(default=None),
):
    """Fetch per-user app state for cross-device sync."""
    user_id = _authorize_user(user_id, authorization)
    default_payload = {
        'selection_change_day': 0,
        'selection_changes_today': 0,
        'opened_video_ids': [],
    }
    if not is_db_enabled():
        return default_payload
    try:
        with get_session() as session:
            if session is None:
                raise HTTPException(
                    status_code=500,
                    detail='database not available',
                )
            state = (
                session.query(UserState)
                .filter(UserState.user_id == user_id)
                .first()
            )
            if state is None:
                return default_payload
            try:
                raw_ids = json.loads(state.opened_video_ids or '[]')
                if not isinstance(raw_ids, list):
                    raw_ids = []
            except ValueError:
                raw_ids = []
            opened_video_ids = _normalize_opened_video_ids(
                [str(item) for item in raw_ids]
            )
            return {
                'selection_change_day': _sanitize_selection_change_day(
                    state.selection_change_day
                ),
                'selection_changes_today': _sanitize_selection_changes_today(
                    state.selection_changes_today
                ),
                'opened_video_ids': opened_video_ids,
            }
    except SQLAlchemyError:
        return default_payload


@app.post('/user/state')
def upsert_user_state(
    req: UserStateUpsertRequest,
    authorization: Optional[str] = Header(default=None),
):
    """Upsert per-user app state for cross-device sync."""
    user_id = _authorize_user(req.user_id, authorization)
    selection_change_day = _sanitize_selection_change_day(
        req.selection_change_day
    )
    selection_changes_today = _sanitize_selection_changes_today(
        req.selection_changes_today
    )
    opened_video_ids = _normalize_opened_video_ids(req.opened_video_ids)
    payload = {
        'selection_change_day': selection_change_day,
        'selection_changes_today': selection_changes_today,
        'opened_video_ids': opened_video_ids,
    }
    if not is_db_enabled():
        return payload
    try:
        with get_session() as session:
            if session is None:
                raise HTTPException(
                    status_code=500,
                    detail='database not available',
                )
            user = session.query(User).filter(User.id == user_id).first()
            if user is None:
                user = User(id=user_id, plan_tier='free')
                session.add(user)
                session.flush()

            state = (
                session.query(UserState)
                .filter(UserState.user_id == user_id)
                .first()
            )
            if state is None:
                state = UserState(user_id=user_id)

            state.selection_change_day = selection_change_day
            state.selection_changes_today = selection_changes_today
            state.opened_video_ids = json.dumps(opened_video_ids)
            state.updated_at = datetime.now(timezone.utc)
            session.add(state)
            session.commit()
            return payload
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=500, detail='user state upsert failed'
        ) from exc


@app.get('/selection')
def get_selection(
    user_id: str,
    authorization: Optional[str] = Header(default=None),
):
    """Return selected channel IDs for a user."""
    user_id = _authorize_user(user_id, authorization)
    if not is_db_enabled():
        return {'selected_ids': []}
    try:
        with get_session() as session:
            if session is None:
                raise HTTPException(
                    status_code=500,
                    detail='database not available',
                )
            rows = (
                session.query(UserChannel)
                .filter(
                    UserChannel.user_id == user_id,
                    UserChannel.is_selected.is_(True),
                )
                .all()
            )
            return {'selected_ids': [row.channel_id for row in rows]}
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=500, detail='selection fetch failed'
        ) from exc


@app.post('/selection')
def save_selection(
    req: SelectionRequest,
    authorization: Optional[str] = Header(default=None),
):
    """Save selected channels for a user."""
    user_id = _authorize_user(req.user_id, authorization)
    if len(req.channels) > MAX_SELECTION_CHANNELS:
        raise HTTPException(
            status_code=413,
            detail='too many channels in selection payload',
        )
    selected_ids = {
        cid.strip()
        for cid in req.selected_ids
        if CHANNEL_ID_PATTERN.fullmatch(cid.strip())
    }
    if len(selected_ids) > MAX_SELECTION_CHANNELS:
        raise HTTPException(
            status_code=413,
            detail='too many selected ids in payload',
        )
    normalized_channels = {}
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
    if channel_ids:
        selected_ids = {cid for cid in selected_ids if cid in channel_ids}
    else:
        selected_ids = set()
    selected_ids_sorted = sorted(selected_ids)
    if not is_db_enabled():
        return {'selected_ids': selected_ids_sorted}
    try:
        with get_session() as session:
            if session is None:
                raise HTTPException(
                    status_code=500,
                    detail='database not available',
                )
            # Ensure user exists
            user = session.query(User).filter(User.id == user_id).first()
            if user is None:
                user = User(id=user_id, plan_tier='free')
                session.add(user)

            # Bulk fetch once to avoid N+1 channel lookups.
            existing_channels = {}
            if channel_ids:
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

            existing_links = (
                session.query(UserChannel)
                .filter(UserChannel.user_id == user_id)
                .all()
            )
            links_by_channel_id = {
                row.channel_id: row for row in existing_links if row.channel_id
            }
            desired = set(selected_ids_sorted)
            for channel_id, row in links_by_channel_id.items():
                if channel_id not in desired:
                    session.delete(row)

            now = datetime.now(timezone.utc)
            for channel_id in desired:
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

            session.commit()
            return {'selected_ids': selected_ids_sorted}
    except IntegrityError as exc:
        raise HTTPException(
            status_code=409, detail='selection conflict'
        ) from exc
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=500, detail='selection save failed'
        ) from exc


def _ensure_archive_video(session, video_id: str) -> None:
    """Create placeholder channel/video rows for archive foreign keys."""
    channel = (
        session.query(Channel)
        .filter(Channel.id == ARCHIVE_PLACEHOLDER_CHANNEL_ID)
        .first()
    )
    if channel is None:
        session.add(
            Channel(
                id=ARCHIVE_PLACEHOLDER_CHANNEL_ID,
                youtube_channel_id=ARCHIVE_PLACEHOLDER_CHANNEL_ID,
                title=ARCHIVE_PLACEHOLDER_CHANNEL_TITLE,
                thumbnail_url=None,
            )
        )
        session.flush()

    existing_video = session.query(Video).filter(Video.id == video_id).first()
    if existing_video is None:
        session.add(
            Video(
                id=video_id,
                youtube_id=video_id[:32],
                channel_id=ARCHIVE_PLACEHOLDER_CHANNEL_ID,
                title=ARCHIVE_PLACEHOLDER_VIDEO_TITLE,
                published_at=None,
            )
        )
        session.flush()


def _sanitize_max_chars(max_chars: Optional[int]) -> int:
    if max_chars is None:
        return TRANSCRIPT_DEFAULT_MAX_CHARS
    return max(
        TRANSCRIPT_MIN_MAX_CHARS,
        min(TRANSCRIPT_MAX_MAX_CHARS, int(max_chars)),
    )


def trim_text(text: str, max_chars: Optional[int]) -> tuple[str, bool]:
    """Trim text to max_chars and return (text, partial)."""
    if not max_chars or len(text) <= max_chars:
        return text, False
    return text[:max_chars].rstrip() + '…', True


def build_summary(text: str, lines: Optional[int]) -> Optional[str]:
    """Build a normalized summary for the given text."""
    if not text.strip():
        return None
    if not OPENAI_API_KEY:
        return None

    target_lines = max(1, min(5, lines or 3))
    summary_input = text
    if 0 < OPENAI_SUMMARY_INPUT_CHARS < len(summary_input):
        summary_input = summary_input[:OPENAI_SUMMARY_INPUT_CHARS]

    summary = summarize_text(summary_input, target_lines)
    if not summary:
        return None
    return normalize_summary(summary, target_lines)


def summarize_text(text: str, lines: int) -> Optional[str]:
    """Call OpenAI to summarize the text into a given number of lines."""
    url = 'https://api.openai.com/v1/chat/completions'
    headers = {
        'Authorization': f'Bearer {OPENAI_API_KEY}',
        'Content-Type': 'application/json',
    }
    prompt = (
        f'다음 내용을 한국어로 {lines}줄 요약해줘.\\n'
        '- 각 줄은 한 문장\\n'
        "- 각 줄은 '• '로 시작\\n"
        f'- 줄바꿈으로만 {lines}줄 출력\\n'
        '- 과장 없이 핵심 사실만\\n\\n'
        f'{text}'
    )
    payload = {
        'model': OPENAI_SUMMARY_MODEL,
        'temperature': 0.2,
        'max_tokens': OPENAI_SUMMARY_MAX_TOKENS,
        'messages': [
            {
                'role': 'system',
                'content': '너는 텍스트를 간결하게 요약하는 한국어 요약 전문가다.',
            },
            {
                'role': 'user',
                'content': prompt,
            },
        ],
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=60)
    except requests.RequestException:
        return None

    if response.status_code != 200:
        return None

    try:
        data = response.json()
    except ValueError:
        return None
    choices = data.get('choices') or []
    if not choices:
        return None
    message = choices[0].get('message') or {}
    content = message.get('content')
    return content if isinstance(content, str) else None


def normalize_summary(summary: str, lines: int) -> str:
    """Normalize summary output to the requested line count."""
    normalized = summary.replace('\\\\n', '\n').replace('\\n', '\n')
    raw_lines = [
        line.strip()
        for line in normalized.splitlines()
        if line.strip()
    ]
    cleaned_lines = []
    for line in raw_lines:
        cleaned = re.sub(r'^[\\s•\\-\\d\\.]+', '', line).strip()
        if cleaned:
            cleaned_lines.append(cleaned)

    if len(cleaned_lines) >= lines:
        return '\n'.join(cleaned_lines[:lines])

    sentence_parts = re.split(r'(?<=[.!?。])\\s+', normalized)
    sentence_parts = [part.strip() for part in sentence_parts if part.strip()]
    if len(sentence_parts) >= lines:
        return '\n'.join(sentence_parts[:lines])

    return normalized.strip()


def load_cache(video_id: str) -> Optional[dict]:
    """Load transcript cache from DB or local file."""
    cached = _load_cache_from_db(video_id)
    if cached:
        return cached
    return _load_cache_from_file(video_id)


def save_cache(video_id: str, payload: dict) -> None:
    """Persist transcript cache to DB or local file."""
    if _save_cache_to_db(video_id, payload):
        return
    _save_cache_to_file(video_id, payload)


def _load_cache_from_db(video_id: str) -> Optional[dict]:
    if not is_db_enabled():
        return None
    try:
        with get_session() as session:
            if session is None:
                return None
            cached = (
                session.query(TranscriptCache)
                .filter(TranscriptCache.video_id == video_id)
                .first()
            )
            if cached is None:
                return None
            created_at = (
                cached.created_at.timestamp() if cached.created_at else None
            )
            if created_at and (time.time() - created_at) > TRANSCRIPT_CACHE_TTL:
                session.delete(cached)
                session.commit()
                return None
            return {
                'text': cached.text or '',
                'summary': cached.summary,
                'source': cached.source or 'captions',
                'partial': bool(cached.partial),
            }
    except SQLAlchemyError:
        return None


def _save_cache_to_db(video_id: str, payload: dict) -> bool:
    if not is_db_enabled():
        return False
    try:
        with get_session() as session:
            if session is None:
                return False
            cached = (
                session.query(TranscriptCache)
                .filter(TranscriptCache.video_id == video_id)
                .first()
            )
            if cached is None:
                cached = TranscriptCache(video_id=video_id)
            cached.text = payload.get('text', '')
            cached.summary = payload.get('summary')
            cached.source = payload.get('source', 'captions')
            cached.partial = bool(payload.get('partial', False))
            cached.created_at = datetime.now(timezone.utc)
            session.add(cached)
            session.commit()
            return True
    except SQLAlchemyError:
        return False


def _load_cache_from_file(video_id: str) -> Optional[dict]:
    if not VIDEO_ID_PATTERN.fullmatch(video_id):
        return None
    path = CACHE_DIR / f'{video_id}.json'
    if not path.exists():
        return None

    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return None

    created_at = data.get('created_at')
    if created_at and (time.time() - created_at) > TRANSCRIPT_CACHE_TTL:
        try:
            path.unlink()
        except OSError:
            pass
        return None

    return {
        'text': data.get('text', ''),
        'summary': data.get('summary'),
        'source': data.get('source', 'captions'),
        'partial': data.get('partial', False),
    }


def _save_cache_to_file(video_id: str, payload: dict) -> None:
    if not VIDEO_ID_PATTERN.fullmatch(video_id):
        return
    path = CACHE_DIR / f'{video_id}.json'
    temp_path = CACHE_DIR / f'{video_id}.tmp'
    data = {
        'text': payload.get('text', ''),
        'summary': payload.get('summary'),
        'source': payload.get('source', 'captions'),
        'partial': payload.get('partial', False),
        'created_at': time.time(),
    }
    try:
        temp_path.write_text(
            json.dumps(data, ensure_ascii=False), encoding='utf-8'
        )
        temp_path.replace(path)
    except OSError:
        pass


def _archive_cache_path(user_id: str) -> Path:
    safe = re.sub(r'[^a-zA-Z0-9_-]+', '_', user_id)
    return CACHE_DIR / f'archive_{safe}.json'


def _load_archives_file(user_id: str) -> list[dict]:
    path = _archive_cache_path(user_id)
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(data, list):
        return []
    items = []
    for entry in data:
        if not isinstance(entry, dict):
            continue
        video_id = entry.get('video_id')
        archived_at = entry.get('archived_at')
        if isinstance(video_id, str) and isinstance(archived_at, int):
            items.append({'video_id': video_id, 'archived_at': archived_at})
    return items


def _save_archives_file(user_id: str, items: list[dict]) -> None:
    path = _archive_cache_path(user_id)
    try:
        path.write_text(json.dumps(items, ensure_ascii=False), encoding='utf-8')
    except OSError:
        pass


def _toggle_archive_file(user_id: str, video_id: str) -> dict:
    items = _load_archives_file(user_id)
    for idx, entry in enumerate(items):
        if entry.get('video_id') == video_id:
            items.pop(idx)
            _save_archives_file(user_id, items)
            return {'archived': False}
    archived_at = int(time.time() * 1000)
    items.append({'video_id': video_id, 'archived_at': archived_at})
    _save_archives_file(user_id, items)
    return {'archived': True, 'archived_at': archived_at}


def fetch_caption_text(video_id: str) -> Optional[str]:
    """Fetch captions via timedtext API (preferred) for a video."""
    tracks = fetch_caption_tracks(video_id)
    track = pick_track(tracks)
    if not track:
        return None

    text = download_caption_text(video_id, track)
    return text if text else None


def fetch_caption_text_via_ytdlp(video_id: str) -> Optional[str]:
    """Fetch captions via yt-dlp extraction."""
    info = fetch_ytdlp_info(video_id)
    if not info and not YTDLP_COOKIES_FROM_BROWSER:
        info = fetch_ytdlp_info(video_id, cookies_from_browser='chrome')
    if not info and not YTDLP_COOKIES_FROM_BROWSER:
        info = fetch_ytdlp_info(video_id, cookies_from_browser='safari')
    if not info:
        return None

    subtitles = info.get('subtitles') or {}
    auto_captions = info.get('automatic_captions') or {}

    preferred = pick_lang_entries(subtitles)
    if not preferred:
        preferred = pick_lang_entries(auto_captions)

    if not preferred:
        return None

    for entry in sort_caption_entries(preferred):
        url = entry.get('url')
        if not url:
            continue
        ext = entry.get('ext')
        text = download_caption_payload(url, ext)
        if text:
            return text
    return None


def fetch_ytdlp_info(
    video_id: str,
    cookies_from_browser: Optional[str] = None,
) -> Optional[dict]:
    """Retrieve yt-dlp metadata for a video."""
    url = f'https://www.youtube.com/watch?v={video_id}'
    player_clients = [
        c.strip()
        for c in YTDLP_PLAYER_CLIENTS.split(',')
        if c.strip()
    ]
    ydl_opts = {
        'quiet': True,
        'skip_download': True,
        'writesubtitles': True,
        'writeautomaticsub': True,
        'subtitleslangs': ['ko', 'en'],
        'geo_bypass': True,
        'extractor_args': {
            'youtube': {
                'player_client': player_clients or ['android', 'web'],
            }
        },
    }
    if YTDLP_COOKIES_PATH:
        ydl_opts['cookiefile'] = YTDLP_COOKIES_PATH
    cookies_from_browser = cookies_from_browser or YTDLP_COOKIES_FROM_BROWSER
    if cookies_from_browser:
        ydl_opts['cookiesfrombrowser'] = (cookies_from_browser,)

    try:
        with YoutubeDL(ydl_opts) as ydl:
            return ydl.extract_info(url, download=False)
    except Exception:
        return None


def pick_lang_entries(tracks: dict) -> list[dict]:
    """Pick language entries preferring Korean then English."""
    if not tracks:
        return []

    def find_by_prefix(prefix: str) -> Optional[list[dict]]:
        for lang, entries in tracks.items():
            if lang.lower().startswith(prefix) and isinstance(entries, list):
                return entries
        return None

    return (
        find_by_prefix('ko')
        or find_by_prefix('en')
        or next(iter(tracks.values()), [])
    )


def sort_caption_entries(entries: list[dict]) -> list[dict]:
    """Sort caption entries by preferred formats."""
    order = ['vtt', 'json3', 'srv3', 'srv2', 'srv1', 'ttml', 'xml']

    def score(entry: dict) -> int:
        ext = (entry.get('ext') or '').lower()
        return order.index(ext) if ext in order else len(order)

    return sorted(entries, key=score)


def fetch_caption_tracks(video_id: str) -> list[dict]:
    """Fetch caption track metadata using timedtext list."""
    url = 'https://www.youtube.com/api/timedtext'
    params = {'type': 'list', 'v': video_id}
    try:
        response = requests.get(
            url, params=params, headers=DEFAULT_HEADERS, timeout=10
        )
    except requests.RequestException:
        return []
    if response.status_code != 200 or not response.text:
        return []

    tracks = []
    for match in re.finditer(r'<track ([^>]+)/?>', response.text):
        attrs = match.group(1)
        lang_match = re.search(r'lang_code="([^"]+)"', attrs)
        kind_match = re.search(r'kind="([^"]+)"', attrs)
        if not lang_match:
            continue
        kind = kind_match.group(1) if kind_match else None
        tracks.append({'lang': lang_match.group(1), 'kind': kind})
    return tracks


def pick_track(tracks: list[dict]) -> Optional[dict]:
    """Pick a caption track preferring Korean then English."""
    if not tracks:
        return None

    def pick(prefix: str):
        for track in tracks:
            if track['lang'].lower().startswith(prefix):
                return track
        return None

    return pick('ko') or pick('en') or tracks[0]


def download_caption_text(video_id: str, track: dict) -> Optional[str]:
    """Download and parse caption text for a specific track."""
    url = 'https://www.youtube.com/api/timedtext'
    formats = ['vtt', 'json3', 'srv3', 'ttml', None]

    for fmt in formats:
        params = {
            'v': video_id,
            'lang': track['lang'],
        }
        if fmt:
            params['fmt'] = fmt
        if track.get('kind'):
            params['kind'] = track['kind']

        try:
            response = requests.get(
                url, params=params, headers=DEFAULT_HEADERS, timeout=10
            )
        except requests.RequestException:
            continue
        if response.status_code != 200 or not response.text:
            continue
        parsed = parse_caption_payload(response.text, fmt)
        if parsed:
            return parsed
    return None


def parse_vtt(raw: str) -> str:
    """Parse WebVTT caption payload into plain text."""
    lines = raw.splitlines()
    buffer = []
    for line in lines:
        trimmed = line.strip()
        if not trimmed:
            continue
        if trimmed == 'WEBVTT':
            continue
        if '-->' in trimmed:
            continue
        if re.match(r'^\d+$', trimmed):
            continue
        cleaned = re.sub(r'<[^>]+>', '', trimmed)
        if cleaned:
            buffer.append(cleaned)
    return ' '.join(buffer).strip()


def download_caption_payload(url: str, ext: Optional[str]) -> Optional[str]:
    """Download caption payload and parse based on format."""
    try_urls = [url]
    if 'fmt=' not in url:
        joiner = '&' if '?' in url else '?'
        try_urls.append(f'{url}{joiner}fmt=vtt')

    for target in try_urls:
        try:
            response = requests.get(target, headers=DEFAULT_HEADERS, timeout=10)
        except requests.RequestException:
            continue
        if response.status_code != 200 or not response.text:
            continue
        text = parse_caption_payload(response.text, ext)
        if text:
            return text
    return None


def parse_caption_payload(raw: str, ext: Optional[str]) -> Optional[str]:
    """Parse caption payload text into plain text."""
    lowered = (ext or '').lower()
    if lowered == 'vtt' or raw.lstrip().startswith('WEBVTT'):
        return parse_vtt(raw)

    if lowered == 'json3' or raw.lstrip().startswith('{'):
        parsed = parse_json3(raw)
        if parsed:
            return parsed

    if '<text' in raw or '<transcript' in raw:
        return parse_timedtext_xml(raw)

    if '<p' in raw and '</p>' in raw:
        return parse_ttml(raw)

    return None


def parse_json3(raw: str) -> Optional[str]:
    """Parse JSON3 caption payload into plain text."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    events = data.get('events') or []
    chunks = []
    for event in events:
        segs = event.get('segs') or []
        for seg in segs:
            text = seg.get('utf8')
            if text:
                chunks.append(text)
    joined = ''.join(chunks)
    cleaned = re.sub(r'\s+', ' ', joined).strip()
    return cleaned or None


def parse_timedtext_xml(raw: str) -> Optional[str]:
    """Parse timedtext XML captions into plain text."""
    chunks = re.findall(r'<text[^>]*>(.*?)</text>', raw, flags=re.DOTALL)
    if not chunks:
        return None
    cleaned = []
    for chunk in chunks:
        chunk = html.unescape(chunk)
        chunk = re.sub(r'<[^>]+>', '', chunk)
        chunk = chunk.replace('\n', ' ').strip()
        if chunk:
            cleaned.append(chunk)
    return ' '.join(cleaned).strip() if cleaned else None


def parse_ttml(raw: str) -> Optional[str]:
    """Parse TTML captions into plain text."""
    chunks = re.findall(r'<p[^>]*>(.*?)</p>', raw, flags=re.DOTALL)
    if not chunks:
        return None
    cleaned = []
    for chunk in chunks:
        chunk = html.unescape(chunk)
        chunk = re.sub(r'<[^>]+>', '', chunk)
        chunk = chunk.replace('\n', ' ').strip()
        if chunk:
            cleaned.append(chunk)
    return ' '.join(cleaned).strip() if cleaned else None


def download_audio(video_id: str) -> tuple[Optional[str], Optional[str]]:
    """Download audio for a video and return local path + error."""
    url = f'https://www.youtube.com/watch?v={video_id}'
    with tempfile.TemporaryDirectory() as tmpdir:
        output = os.path.join(tmpdir, f'{video_id}.%(ext)s')
        player_clients = [
            c.strip()
            for c in YTDLP_PLAYER_CLIENTS.split(',')
            if c.strip()
        ]
        ydl_opts = {
            'format': 'bestaudio[ext=m4a]/bestaudio/best',
            'outtmpl': output,
            'quiet': True,
            'noplaylist': True,
            'geo_bypass': True,
            'extractor_args': {
                'youtube': {
                    'player_client': player_clients or ['android', 'web'],
                }
            },
        }
        if YTDLP_COOKIES_PATH:
            ydl_opts['cookiefile'] = YTDLP_COOKIES_PATH
        if YTDLP_COOKIES_FROM_BROWSER:
            ydl_opts['cookiesfrombrowser'] = (YTDLP_COOKIES_FROM_BROWSER,)
        try:
            with YoutubeDL(ydl_opts) as ydl:
                ydl.extract_info(url, download=True)
        except DownloadError as error:
            if not YTDLP_COOKIES_FROM_BROWSER:
                try:
                    with YoutubeDL(
                        {**ydl_opts, 'cookiesfrombrowser': ('chrome',)}
                    ) as ydl:
                        ydl.extract_info(url, download=True)
                except Exception as retry_error:
                    return None, str(retry_error)
            return None, str(error)
        except Exception as error:
            return None, str(error)

        files = list(Path(tmpdir).glob(f'{video_id}.*'))
        if not files:
            return None, '음성 파일을 찾지 못했습니다.'
        source = files[0]
        fd, temp_name = tempfile.mkstemp(
            prefix='youtube-summary-audio-', suffix=source.suffix
        )
        os.close(fd)
        temp_output = Path(temp_name)
        try:
            shutil.copyfile(source, temp_output)
        except OSError as error:
            try:
                temp_output.unlink()
            except OSError:
                pass
            return None, str(error)
        return str(temp_output), None


def is_membership_error(message: str) -> bool:
    """Check if an error message indicates a members-only restriction."""
    lowered = message.lower()
    keywords = [
        'members-only',
        'members only',
        'member-only',
        'membership',
        'join this channel',
        'available to this channel\'s members',
        'only available to channel members',
    ]
    return any(keyword in lowered for keyword in keywords)


def transcribe_audio(path: str) -> Optional[str]:
    """Transcribe audio using OpenAI Whisper API."""
    url = 'https://api.openai.com/v1/audio/transcriptions'
    headers = {
        'Authorization': f'Bearer {OPENAI_API_KEY}',
    }
    with open(path, 'rb') as audio_file:
        files = {'file': audio_file}
        data = {
            'model': 'whisper-1',
            'response_format': 'json',
        }
        try:
            response = requests.post(
                url, headers=headers, files=files, data=data, timeout=120
            )
        except requests.RequestException:
            return None

    if response.status_code != 200:
        return None

    try:
        payload = response.json()
    except ValueError:
        return None
    return payload.get('text')
