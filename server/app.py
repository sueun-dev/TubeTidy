"""FastAPI backend for YouTube Summary."""

from collections import deque
from contextlib import asynccontextmanager, contextmanager
import hashlib
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
from typing import Any, Optional

import requests
import jwt
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
try:
    from sqlalchemy.dialects.postgresql import insert as pg_insert
except Exception:  # pragma: no cover - fallback for non-Postgres builds.
    pg_insert = None
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


def _env_flag(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {'1', 'true', 'yes', 'on'}


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
YTDLP_PLAYER_CLIENT_LIST = tuple(
    client.strip()
    for client in YTDLP_PLAYER_CLIENTS.split(',')
    if client.strip()
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
APP_ENV = os.getenv('APP_ENV', 'development').strip().lower()
BACKEND_REQUIRE_AUTH = _env_flag('BACKEND_REQUIRE_AUTH', True)
ENABLE_API_DOCS = _env_flag('ENABLE_API_DOCS', False)
FAIL_CLOSED_WITHOUT_DB = _env_flag(
    'FAIL_CLOSED_WITHOUT_DB',
    APP_ENV in {'prod', 'production'},
)
TRUST_PROXY_HEADERS = _env_flag('TRUST_PROXY_HEADERS', False)
AUTH_CLOCK_SKEW_SECONDS = int(os.getenv('AUTH_CLOCK_SKEW_SECONDS', '120'))
GOOGLE_JWKS_URL = os.getenv(
    'GOOGLE_JWKS_URL',
    'https://www.googleapis.com/oauth2/v3/certs',
)
GOOGLE_JWKS_TIMEOUT_SECONDS = float(
    os.getenv('GOOGLE_JWKS_TIMEOUT_SECONDS', '5')
)
GOOGLE_JWKS_CACHE_TTL_SECONDS = max(
    60,
    int(os.getenv('GOOGLE_JWKS_CACHE_TTL_SECONDS', '3600')),
)
GOOGLE_ID_TOKEN_ALGORITHMS = tuple(
    alg.strip().upper()
    for alg in os.getenv('GOOGLE_ID_TOKEN_ALGORITHMS', 'RS256').split(',')
    if alg.strip()
) or ('RS256',)
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
WRITE_RATE_LIMIT_PER_WINDOW = int(os.getenv('WRITE_RATE_LIMIT_PER_WINDOW', '60'))
WRITE_RATE_LIMIT_WINDOW_SECONDS = int(
    os.getenv('WRITE_RATE_LIMIT_WINDOW_SECONDS', '60')
)
WRITE_RATE_LOCK = threading.Lock()
WRITE_RATE_BUCKETS: dict[str, deque[float]] = {}
RATE_LIMIT_MAX_BUCKETS = int(os.getenv('RATE_LIMIT_MAX_BUCKETS', '8192'))
GOOGLE_JWKS_ISSUERS = (
    'accounts.google.com',
    'https://accounts.google.com',
)
GOOGLE_JWKS_LOCK = threading.Lock()
GOOGLE_JWKS_BY_KID: dict[str, Any] = {}
GOOGLE_JWKS_EXPIRES_AT = 0.0
CAPTION_FORMAT_PRIORITY = {
    'vtt': 0,
    'json3': 1,
    'srv3': 2,
    'srv2': 3,
    'srv1': 4,
    'ttml': 5,
    'xml': 6,
}


@asynccontextmanager
async def app_lifespan(_: FastAPI):
    """Startup and shutdown lifecycle hooks."""
    if BACKEND_REQUIRE_AUTH and not _configured_client_ids:
        raise RuntimeError(
            'BACKEND_REQUIRE_AUTH=true 이지만 '
            'GOOGLE_CLIENT_IDS/GOOGLE_WEB_CLIENT_ID/GOOGLE_IOS_CLIENT_ID가 '
            '설정되지 않았습니다.'
        )
    if FAIL_CLOSED_WITHOUT_DB and not is_db_enabled():
        raise RuntimeError(
            'FAIL_CLOSED_WITHOUT_DB=true 이지만 DATABASE_URL이 설정되지 않았습니다.'
        )
    init_db()
    if FAIL_CLOSED_WITHOUT_DB and not check_db():
        raise RuntimeError(
            'FAIL_CLOSED_WITHOUT_DB=true 이지만 데이터베이스 연결이 불가능합니다.'
        )
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


def _require_session(session: Any):
    """Return a DB session or raise a consistent HTTP error."""
    if session is None:
        raise HTTPException(
            status_code=503 if FAIL_CLOSED_WITHOUT_DB else 500,
            detail='database required' if FAIL_CLOSED_WITHOUT_DB else 'database not available',
        )
    return session


def _allow_file_fallback() -> bool:
    return not FAIL_CLOSED_WITHOUT_DB


def _require_database_for_write() -> None:
    if FAIL_CLOSED_WITHOUT_DB and not is_db_enabled():
        raise HTTPException(status_code=503, detail='database required')


def _raise_db_unavailable(exc: Optional[Exception] = None) -> None:
    status_code = 503 if FAIL_CLOSED_WITHOUT_DB else 500
    detail = 'database required' if FAIL_CLOSED_WITHOUT_DB else 'database not available'
    raise HTTPException(status_code=status_code, detail=detail) from exc


def _is_postgres_session(session: Any) -> bool:
    bind = getattr(session, 'bind', None)
    dialect = getattr(bind, 'dialect', None)
    return getattr(dialect, 'name', '') == 'postgresql'


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


def _extract_max_age(cache_control: str) -> Optional[int]:
    match = re.search(r'max-age=(\d+)', cache_control)
    if not match:
        return None
    return int(match.group(1))


def _refresh_google_jwks(force_refresh: bool = False) -> dict[str, Any]:
    global GOOGLE_JWKS_EXPIRES_AT
    now = time.time()
    with GOOGLE_JWKS_LOCK:
        if (
            not force_refresh
            and GOOGLE_JWKS_BY_KID
            and GOOGLE_JWKS_EXPIRES_AT > now
        ):
            return GOOGLE_JWKS_BY_KID

        try:
            response = requests.get(
                GOOGLE_JWKS_URL,
                timeout=GOOGLE_JWKS_TIMEOUT_SECONDS,
            )
        except requests.RequestException as exc:
            raise HTTPException(
                status_code=401,
                detail='invalid access token',
            ) from exc

        if response.status_code != 200:
            raise HTTPException(status_code=401, detail='invalid access token')

        try:
            payload = response.json()
        except ValueError as exc:
            raise HTTPException(
                status_code=401,
                detail='invalid access token',
            ) from exc

        keys = payload.get('keys')
        if not isinstance(keys, list):
            raise HTTPException(status_code=401, detail='invalid access token')

        jwks_by_kid: dict[str, Any] = {}
        for key_data in keys:
            if not isinstance(key_data, dict):
                continue
            key_id = key_data.get('kid')
            if not isinstance(key_id, str) or not key_id:
                continue
            try:
                jwks_by_kid[key_id] = jwt.PyJWK.from_dict(key_data).key
            except jwt.PyJWTError:
                continue

        if not jwks_by_kid:
            raise HTTPException(status_code=401, detail='invalid access token')

        max_age = _extract_max_age(response.headers.get('Cache-Control', ''))
        ttl = max_age if max_age is not None else GOOGLE_JWKS_CACHE_TTL_SECONDS
        ttl = max(60, ttl)
        GOOGLE_JWKS_BY_KID.clear()
        GOOGLE_JWKS_BY_KID.update(jwks_by_kid)
        GOOGLE_JWKS_EXPIRES_AT = now + ttl
        return GOOGLE_JWKS_BY_KID


def _resolve_google_signing_key(token: str):
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail='invalid access token') from exc

    algorithm = (header.get('alg') or '').upper()
    if algorithm not in GOOGLE_ID_TOKEN_ALGORITHMS:
        raise HTTPException(status_code=401, detail='invalid token algorithm')

    key_id = header.get('kid')
    if not isinstance(key_id, str) or not key_id.strip():
        raise HTTPException(status_code=401, detail='invalid access token')

    key_map = _refresh_google_jwks()
    key = key_map.get(key_id)
    if key is None:
        key_map = _refresh_google_jwks(force_refresh=True)
        key = key_map.get(key_id)
    if key is None:
        raise HTTPException(status_code=401, detail='invalid access token')
    return key


def _extract_audiences(payload: dict[str, Any]) -> set[str]:
    audience_claim = payload.get('aud')
    if isinstance(audience_claim, str):
        return {audience_claim}
    if isinstance(audience_claim, list):
        values = {item for item in audience_claim if isinstance(item, str)}
        if values and len(values) == len(audience_claim):
            return values
    raise HTTPException(status_code=401, detail='token audience invalid')


def _validate_google_token_claims(payload: dict[str, Any]) -> str:
    issuer = payload.get('iss')
    if issuer not in GOOGLE_JWKS_ISSUERS:
        raise HTTPException(status_code=401, detail='token issuer mismatch')

    audiences = _extract_audiences(payload)
    if _configured_client_ids and not audiences.intersection(_configured_client_ids):
        raise HTTPException(status_code=401, detail='token audience mismatch')

    authorized_party = payload.get('azp')
    if isinstance(payload.get('aud'), list) and len(audiences) > 1:
        if not isinstance(authorized_party, str) or not authorized_party:
            raise HTTPException(status_code=401, detail='token azp missing')
        if authorized_party not in audiences:
            raise HTTPException(status_code=401, detail='token azp mismatch')
    if isinstance(authorized_party, str) and _configured_client_ids:
        if authorized_party not in _configured_client_ids:
            raise HTTPException(status_code=401, detail='token azp mismatch')

    subject = payload.get('sub')
    if not isinstance(subject, str) or not USER_ID_PATTERN.fullmatch(subject):
        raise HTTPException(status_code=401, detail='invalid token subject')
    return subject


def _verify_google_user(token: str) -> str:
    now = time.time()
    with AUTH_CACHE_LOCK:
        cached = AUTH_CACHE.get(token)
        if cached and cached[0] > now:
            return cached[1]

    try:
        signing_key = _resolve_google_signing_key(token)
        payload = jwt.decode(
            token,
            signing_key,
            algorithms=list(GOOGLE_ID_TOKEN_ALGORITHMS),
            options={
                'require': ['exp', 'iss', 'sub', 'aud'],
                'verify_aud': False,
            },
            leeway=AUTH_CLOCK_SKEW_SECONDS,
        )
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(status_code=401, detail='token expired') from exc
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail='invalid access token') from exc

    subject = _validate_google_token_claims(payload)
    expires_at = payload.get('exp')
    try:
        expiry = float(expires_at)
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=401, detail='token exp invalid') from exc

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
    if TRUST_PROXY_HEADERS:
        forwarded = request.headers.get('x-forwarded-for', '')
        if forwarded:
            candidate = forwarded.split(',')[0].strip()
            if candidate:
                return candidate[:128]
    client = request.client.host if request.client else 'unknown'
    return (client or 'unknown')[:128]


def _enforce_rate_limit(
    *,
    key: str,
    per_window: int,
    window_seconds: int,
    lock: threading.Lock,
    buckets: dict[str, deque[float]],
) -> None:
    if per_window <= 0:
        return
    now = time.monotonic()
    cutoff = now - max(1, window_seconds)
    with lock:
        bucket = buckets.setdefault(key, deque())
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= per_window:
            raise HTTPException(
                status_code=429,
                detail='요청이 많아 잠시 후 다시 시도해주세요.',
            )
        bucket.append(now)
        if len(buckets) > RATE_LIMIT_MAX_BUCKETS:
            stale_keys = [
                bucket_key
                for bucket_key, values in buckets.items()
                if not values or values[-1] < cutoff
            ]
            for stale_key in stale_keys:
                buckets.pop(stale_key, None)


def _enforce_transcript_rate_limit(client_id: str) -> None:
    _enforce_rate_limit(
        key=f'transcript:{client_id}',
        per_window=TRANSCRIPT_RATE_LIMIT_PER_WINDOW,
        window_seconds=TRANSCRIPT_RATE_LIMIT_WINDOW_SECONDS,
        lock=TRANSCRIPT_RATE_LOCK,
        buckets=TRANSCRIPT_RATE_BUCKETS,
    )


def _enforce_write_rate_limit(request: Request, user_id: Optional[str] = None) -> None:
    principal = f'user:{user_id}' if user_id else f'ip:{_resolve_client_id(request)}'
    _enforce_rate_limit(
        key=f'write:{principal}',
        per_window=WRITE_RATE_LIMIT_PER_WINDOW,
        window_seconds=WRITE_RATE_LIMIT_WINDOW_SECONDS,
        lock=WRITE_RATE_LOCK,
        buckets=WRITE_RATE_BUCKETS,
    )


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


def _build_transcript_payload(
    source_text: str,
    *,
    source: str,
    summarize: bool,
    summary_lines: Optional[int],
    max_chars: int,
) -> dict[str, Any]:
    text, partial = trim_text(source_text, max_chars)
    summary = build_summary(source_text, summary_lines) if summarize else None
    return {
        'text': text,
        'summary': summary,
        'source': source,
        'partial': partial,
    }


def _resolve_audio_download_detail(error: Optional[str]) -> str:
    detail = '음성 다운로드에 실패했습니다.'
    if not error:
        return detail
    if is_membership_error(error):
        return 'You might not have membership for this video.'
    if 'HTTP Error 403' in error or 'Forbidden' in error:
        return (
            '음성 다운로드가 차단되었습니다. '
            'YouTube 제한(로그인/연령/지역) 또는 다운로더 업데이트가 필요합니다.'
        )
    return detail


def _normalize_selection_request(
    req: SelectionRequest,
) -> tuple[dict[str, dict[str, Optional[str]]], list[str]]:
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
        cid for cid in selected_ids if cid in channel_ids
    )
    return normalized_channels, normalized_selected_ids


def _ensure_user_exists(session: Any, user_id: str) -> None:
    if _is_postgres_session(session) and pg_insert is not None:
        stmt = (
            pg_insert(User.__table__)
            .values(id=user_id, plan_tier='free')
            .on_conflict_do_nothing(index_elements=['id'])
        )
        session.execute(stmt)
        return

    user = session.query(User).filter(User.id == user_id).first()
    if user is None:
        session.add(User(id=user_id, plan_tier='free'))
        session.flush()


def _upsert_channels(
    session: Any,
    normalized_channels: dict[str, dict[str, Optional[str]]],
) -> None:
    channel_ids = set(normalized_channels.keys())
    if not channel_ids:
        return

    if _is_postgres_session(session) and pg_insert is not None:
        values = [
            {
                'id': channel_id,
                'youtube_channel_id': channel_id,
                'title': payload['title'],
                'thumbnail_url': payload['thumbnail_url'],
            }
            for channel_id, payload in normalized_channels.items()
        ]
        insert_stmt = pg_insert(Channel.__table__).values(values)
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


def _sync_user_channel_links(
    session: Any,
    user_id: str,
    selected_ids_sorted: list[str],
) -> None:
    now = datetime.now(timezone.utc)
    if _is_postgres_session(session) and pg_insert is not None:
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
                pg_insert(UserChannel.__table__)
                .values(values)
                .on_conflict_do_update(
                    index_elements=['user_id', 'channel_id'],
                    set_={
                        'is_selected': True,
                        'synced_at': now,
                    },
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


@app.post('/transcript')
def transcript(req: TranscriptRequest, request: Request):
    """Return transcript and summary for a YouTube video."""
    _enforce_transcript_rate_limit(_resolve_client_id(request))
    video_id = _sanitize_video_id(req.video_id)
    max_chars = _sanitize_max_chars(req.max_chars)
    cache_key = _build_transcript_cache_key(
        video_id=video_id,
        max_chars=max_chars,
        summarize=bool(req.summarize),
        summary_lines=req.summary_lines,
    )

    cached = load_cache(cache_key)
    if cached:
        return {**cached, 'cached': True}

    with _transcript_slot(TRANSCRIPT_QUEUE_TIMEOUT):
        caption_text = fetch_caption_text(video_id)
        if not caption_text:
            caption_text = fetch_caption_text_via_ytdlp(video_id)

        if caption_text:
            payload = _build_transcript_payload(
                caption_text,
                source='captions',
                summarize=req.summarize,
                summary_lines=req.summary_lines,
                max_chars=max_chars,
            )
            save_cache(cache_key, payload)
            return {**payload, 'cached': False}

        if not OPENAI_API_KEY:
            raise HTTPException(
                status_code=400,
                detail='OPENAI_API_KEY가 설정되어 있지 않습니다.',
            )

        audio_path, error = download_audio(video_id)
        if audio_path is None:
            raise HTTPException(
                status_code=500,
                detail=_resolve_audio_download_detail(error),
            )

        try:
            transcript_text = transcribe_audio(audio_path)
        finally:
            try:
                os.remove(audio_path)
            except OSError:
                pass

        if not transcript_text:
            raise HTTPException(status_code=500, detail='음성 인식에 실패했습니다.')

        payload = _build_transcript_payload(
            transcript_text,
            source='whisper',
            summarize=req.summarize,
            summary_lines=req.summary_lines,
            max_chars=max_chars,
        )
        save_cache(cache_key, payload)
        return {**payload, 'cached': False}


@app.get('/archives')
def list_archives(
    user_id: str,
    authorization: Optional[str] = Header(default=None),
):
    """List archived videos for a user."""
    user_id = _authorize_user(user_id, authorization)
    if FAIL_CLOSED_WITHOUT_DB and not is_db_enabled():
        raise HTTPException(status_code=503, detail='database required')
    if is_db_enabled():
        try:
            with get_session() as session:
                if session is None:
                    _raise_db_unavailable()
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
        except SQLAlchemyError as exc:
            if FAIL_CLOSED_WITHOUT_DB:
                raise HTTPException(
                    status_code=503,
                    detail='database required',
                ) from exc
            return {'items': []}
    if not _allow_file_fallback():
        raise HTTPException(status_code=503, detail='database required')
    return {'items': _load_archives_file(user_id)}


@app.post('/archives/toggle')
def toggle_archive(
    req: ArchiveToggleRequest,
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    """Toggle archive status for a video."""
    user_id = _authorize_user(req.user_id, authorization)
    _enforce_write_rate_limit(request, user_id)
    video_id = _sanitize_archive_video_id(req.video_id)
    _require_database_for_write()

    if is_db_enabled():
        try:
            with get_session() as session:
                if session is None:
                    _raise_db_unavailable()
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
            if FAIL_CLOSED_WITHOUT_DB:
                raise HTTPException(
                    status_code=503,
                    detail='database required',
                ) from exc
            raise HTTPException(
                status_code=500, detail='archive update failed'
            ) from exc

    if not _allow_file_fallback():
        raise HTTPException(status_code=503, detail='database required')
    return _toggle_archive_file(user_id, video_id)


@app.post('/archives/clear')
def clear_archives(
    req: ArchiveClearRequest,
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    """Clear all archive entries for a user."""
    user_id = _authorize_user(req.user_id, authorization)
    _enforce_write_rate_limit(request, user_id)
    _require_database_for_write()

    if is_db_enabled():
        try:
            with get_session() as session:
                if session is None:
                    _raise_db_unavailable()
                session.query(Archive).filter(
                    Archive.user_id == user_id
                ).delete()
                session.commit()
                return {'cleared': True}
        except SQLAlchemyError as exc:
            if FAIL_CLOSED_WITHOUT_DB:
                raise HTTPException(
                    status_code=503,
                    detail='database required',
                ) from exc
            raise HTTPException(
                status_code=500, detail='archive clear failed'
            ) from exc

    if not _allow_file_fallback():
        raise HTTPException(status_code=503, detail='database required')
    _save_archives_file(user_id, [])
    return {'cleared': True}


@app.post('/user/upsert')
def upsert_user(
    req: UserUpsertRequest,
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    """Create or update a user profile."""
    user_id = _authorize_user(req.user_id, authorization)
    _enforce_write_rate_limit(request, user_id)
    email = _sanitize_email(req.email)
    plan_tier = _sanitize_plan_tier(req.plan_tier) if req.plan_tier else None
    _require_database_for_write()
    if not is_db_enabled():
        return {
            'user_id': user_id,
            'email': email,
            'plan_tier': plan_tier or 'free',
        }
    try:
        with get_session() as session:
            if session is None:
                _raise_db_unavailable()
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
        if FAIL_CLOSED_WITHOUT_DB:
            raise HTTPException(
                status_code=503,
                detail='database required',
            ) from exc
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
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    """Update or create the user's plan tier."""
    user_id = _authorize_user(req.user_id, authorization)
    _enforce_write_rate_limit(request, user_id)
    plan_tier = _sanitize_plan_tier(req.plan_tier)
    _require_database_for_write()
    if not is_db_enabled():
        return {'updated': True, 'plan_tier': plan_tier}
    try:
        with get_session() as session:
            if session is None:
                _raise_db_unavailable()
            user = session.query(User).filter(User.id == user_id).first()
            if user is None:
                user = User(id=user_id, plan_tier=plan_tier)
                session.add(user)
            else:
                user.plan_tier = plan_tier
            session.commit()
            return {'updated': True, 'plan_tier': user.plan_tier}
    except SQLAlchemyError as exc:
        if FAIL_CLOSED_WITHOUT_DB:
            raise HTTPException(
                status_code=503,
                detail='database required',
            ) from exc
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
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    """Upsert per-user app state for cross-device sync."""
    user_id = _authorize_user(req.user_id, authorization)
    _enforce_write_rate_limit(request, user_id)
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
    _require_database_for_write()
    if not is_db_enabled():
        return payload
    try:
        with get_session() as session:
            if session is None:
                _raise_db_unavailable()
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
        if FAIL_CLOSED_WITHOUT_DB:
            raise HTTPException(
                status_code=503,
                detail='database required',
            ) from exc
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
            session = _require_session(session)
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
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    """Save selected channels for a user."""
    user_id = _authorize_user(req.user_id, authorization)
    _enforce_write_rate_limit(request, user_id)
    normalized_channels, selected_ids_sorted = _normalize_selection_request(req)
    _require_database_for_write()
    if not is_db_enabled():
        return {'selected_ids': selected_ids_sorted}
    try:
        with get_session() as session:
            session = _require_session(session)
            _ensure_user_exists(session, user_id)
            _upsert_channels(session, normalized_channels)
            _sync_user_channel_links(session, user_id, selected_ids_sorted)

            session.commit()
            return {'selected_ids': selected_ids_sorted}
    except IntegrityError as exc:
        raise HTTPException(
            status_code=409, detail='selection conflict'
        ) from exc
    except SQLAlchemyError as exc:
        if FAIL_CLOSED_WITHOUT_DB:
            raise HTTPException(
                status_code=503,
                detail='database required',
            ) from exc
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
        cleaned = re.sub(r'^[\s•\-\d\.]+', '', line).strip()
        if cleaned:
            cleaned_lines.append(cleaned)

    if len(cleaned_lines) >= lines:
        return '\n'.join(cleaned_lines[:lines])

    sentence_parts = re.split(r'(?<=[.!?。])\s+', normalized)
    sentence_parts = [part.strip() for part in sentence_parts if part.strip()]
    if len(sentence_parts) >= lines:
        return '\n'.join(sentence_parts[:lines])

    return normalized.strip()


def _build_transcript_cache_key(
    *,
    video_id: str,
    max_chars: int,
    summarize: bool,
    summary_lines: Optional[int],
) -> str:
    """Build a stable 32-char cache key per transcript request shape."""
    normalized_lines = max(1, min(5, summary_lines or 3))
    signature = (
        f'video:{video_id}|chars:{max_chars}|'
        f'summarize:{int(summarize)}|lines:{normalized_lines}'
    )
    return hashlib.sha256(signature.encode('utf-8')).hexdigest()[:32]


def load_cache(video_id: str) -> Optional[dict]:
    """Load transcript cache from DB or local file."""
    cached = _load_cache_from_db(video_id)
    if cached:
        return cached
    if not _allow_file_fallback():
        return None
    return _load_cache_from_file(video_id)


def save_cache(video_id: str, payload: dict) -> None:
    """Persist transcript cache to DB or local file."""
    if _save_cache_to_db(video_id, payload):
        return
    if not _allow_file_fallback():
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
    ydl_opts = {
        'quiet': True,
        'skip_download': True,
        'writesubtitles': True,
        'writeautomaticsub': True,
        'subtitleslangs': ['ko', 'en'],
        'geo_bypass': True,
        'extractor_args': {
            'youtube': {
                'player_client': list(YTDLP_PLAYER_CLIENT_LIST)
                or ['android', 'web'],
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
    def score(entry: dict) -> int:
        ext = (entry.get('ext') or '').lower()
        return CAPTION_FORMAT_PRIORITY.get(ext, len(CAPTION_FORMAT_PRIORITY))

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
    if not isinstance(events, list):
        return None
    chunks = []
    for event in events:
        if not isinstance(event, dict):
            continue
        segs = event.get('segs')
        if not isinstance(segs, list):
            continue
        for seg in segs:
            if not isinstance(seg, dict):
                continue
            text = seg.get('utf8')
            if isinstance(text, str) and text:
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
        ydl_opts = {
            'format': 'bestaudio[ext=m4a]/bestaudio/best',
            'outtmpl': output,
            'quiet': True,
            'noplaylist': True,
            'geo_bypass': True,
            'extractor_args': {
                'youtube': {
                    'player_client': list(YTDLP_PLAYER_CLIENT_LIST)
                    or ['android', 'web'],
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
            if YTDLP_COOKIES_FROM_BROWSER:
                return None, str(error)
            try:
                with YoutubeDL(
                    {**ydl_opts, 'cookiesfrombrowser': ('chrome',)}
                ) as ydl:
                    ydl.extract_info(url, download=True)
            except Exception as retry_error:
                return None, str(retry_error)
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
