"""FastAPI backend for YouTube Summary."""

from collections import deque
from contextlib import asynccontextmanager, contextmanager
import hmac
import json
import os
import re
import threading
import time
import uuid
from typing import Any, Optional

import requests
import jwt
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError

from .config import (
    ALLOWED_ORIGINS,
    ALLOW_CLIENT_PLAN_UPDATES,
    ALLOW_CREDENTIALS,
    ARCHIVE_PLACEHOLDER_CHANNEL_ID,
    ARCHIVE_PLACEHOLDER_CHANNEL_TITLE,
    ARCHIVE_PLACEHOLDER_VIDEO_TITLE,
    ARCHIVE_VIDEO_ID_PATTERN,
    AUTH_CACHE_MAX_ITEMS,
    AUTH_CLOCK_SKEW_SECONDS,
    BACKEND_REQUIRE_AUTH,
    CHANNEL_ID_PATTERN,
    CONFIGURED_CLIENT_IDS,
    ENABLE_API_DOCS,
    FAIL_CLOSED_WITHOUT_DB,
    GOOGLE_ID_TOKEN_ALGORITHMS,
    GOOGLE_JWKS_CACHE_TTL_SECONDS,
    GOOGLE_JWKS_ISSUERS,
    GOOGLE_JWKS_TIMEOUT_SECONDS,
    GOOGLE_JWKS_URL,
    MAX_CHANNEL_THUMBNAIL_LENGTH,
    MAX_CHANNEL_TITLE_LENGTH,
    MAX_OPENED_VIDEO_IDS,
    MAX_SELECTION_CHANGE_DAY,
    MAX_SELECTION_CHANGES_TODAY,
    OPENAI_API_KEY,
    OPENAI_SUMMARY_INPUT_CHARS,
    OPENAI_SUMMARY_MAX_TOKENS,
    OPENAI_SUMMARY_MODEL,
    PLAN_CHANNEL_LIMITS,
    PLAN_TIER_PATTERN,
    PLAN_UPDATE_SHARED_SECRET,
    RATE_LIMIT_MAX_BUCKETS,
    TRANSCRIPT_DEFAULT_MAX_CHARS,
    TRANSCRIPT_MAX_MAX_CHARS,
    TRANSCRIPT_MIN_MAX_CHARS,
    TRANSCRIPT_MAX_CONCURRENCY,
    TRANSCRIPT_QUEUE_TIMEOUT,
    TRANSCRIPT_RATE_LIMIT_PER_WINDOW,
    TRANSCRIPT_RATE_LIMIT_WINDOW_SECONDS,
    TRUST_PROXY_HEADERS,
    USER_ID_PATTERN,
    VIDEO_ID_PATTERN,
    WRITE_RATE_LIMIT_PER_WINDOW,
    WRITE_RATE_LIMIT_WINDOW_SECONDS,
    YTDLP_COOKIES_FROM_BROWSER,
    YTDLP_COOKIES_PATH,
    YTDLP_PLAYER_CLIENT_LIST,
    YTDLP_SOCKET_TIMEOUT_SECONDS,
)
from .db import check_db, get_session, is_db_enabled, validate_schema
from .models import (
    Archive,
    Channel,
    User,
    UserChannel,
    UserState,
    Video,
)
from .persistence import (
    ensure_user_exists,
    normalize_selection_request,
    serialize_archive_items,
    sync_user_channel_links,
    upsert_archive_video,
    upsert_channels,
    upsert_user_profile,
    upsert_user_state_row,
)
from .schemas import (
    ArchiveClearRequest,
    ArchiveToggleRequest,
    SelectionRequest,
    TranscriptRequest,
    UserPlanRequest,
    UserStateUpsertRequest,
    UserUpsertRequest,
)
from . import transcript_utils
from .transcript_utils import (
    build_transcript_cache_key,
    load_archives_file,
    load_cache,
    normalize_summary,
    parse_caption_payload,
    parse_json3,
    save_archives_file,
    save_cache,
    sanitize_max_chars,
    toggle_archive_file,
    trim_text,
)

TRANSCRIPT_SEMAPHORE = threading.Semaphore(max(1, TRANSCRIPT_MAX_CONCURRENCY))
AUTH_CACHE_LOCK = threading.Lock()
AUTH_CACHE: dict[str, tuple[float, str]] = {}
TRANSCRIPT_RATE_LOCK = threading.Lock()
TRANSCRIPT_RATE_BUCKETS: dict[str, deque[float]] = {}
WRITE_RATE_LOCK = threading.Lock()
WRITE_RATE_BUCKETS: dict[str, deque[float]] = {}
GOOGLE_JWKS_LOCK = threading.Lock()
GOOGLE_JWKS_BY_KID: dict[str, Any] = {}
GOOGLE_JWKS_STATE = {'expires_at': 0.0}
# Backward-compatible test seam while config moved into server.config.
_configured_client_ids = CONFIGURED_CLIENT_IDS
PUBLIC_TEST_SEAMS = (
    normalize_summary,
    parse_caption_payload,
    parse_json3,
    TRANSCRIPT_DEFAULT_MAX_CHARS,
    TRANSCRIPT_MAX_MAX_CHARS,
    TRANSCRIPT_MIN_MAX_CHARS,
)


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
    if FAIL_CLOSED_WITHOUT_DB and not check_db():
        raise RuntimeError(
            'FAIL_CLOSED_WITHOUT_DB=true 이지만 데이터베이스 연결이 불가능합니다.'
        )
    if is_db_enabled():
        schema_ok, schema_detail = validate_schema()
        if not schema_ok:
            detail = schema_detail or 'unknown schema error'
            raise RuntimeError(
                '데이터베이스 스키마가 준비되지 않았습니다. '
                f'scripts/migrate_db.py를 먼저 실행하세요. ({detail})'
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
    allow_methods=['GET', 'POST', 'OPTIONS'],
    allow_headers=[
        'Authorization',
        'Content-Type',
        'X-Request-Id',
        'X-Plan-Update-Token',
    ],
)


@app.middleware('http')
async def apply_security_headers(request: Request, call_next):
    """Apply basic security headers and correlation id."""
    response = await call_next(request)
    raw_request_id = request.headers.get('X-Request-Id')
    if raw_request_id and re.fullmatch(r'[A-Za-z0-9_\-\.]{1,128}', raw_request_id):
        request_id = raw_request_id
    else:
        request_id = str(uuid.uuid4())
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
            detail=(
                'database required'
                if FAIL_CLOSED_WITHOUT_DB
                else 'database not available'
            ),
        )
    return session


def _allow_file_fallback() -> bool:
    return not FAIL_CLOSED_WITHOUT_DB


def _require_database_for_write() -> None:
    if FAIL_CLOSED_WITHOUT_DB and not is_db_enabled():
        raise HTTPException(status_code=503, detail='database required')


def _raise_db_unavailable(exc: Optional[Exception] = None) -> None:
    status_code = 503 if FAIL_CLOSED_WITHOUT_DB else 500
    detail = (
        'database required'
        if FAIL_CLOSED_WITHOUT_DB
        else 'database not available'
    )
    raise HTTPException(status_code=status_code, detail=detail) from exc


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


def _channel_limit_for_plan_tier(raw_plan_tier: Optional[str]) -> Optional[int]:
    if not raw_plan_tier:
        return PLAN_CHANNEL_LIMITS['free']
    try:
        plan_tier = _sanitize_plan_tier(raw_plan_tier)
    except HTTPException:
        plan_tier = 'free'
    return PLAN_CHANNEL_LIMITS.get(plan_tier, PLAN_CHANNEL_LIMITS['free'])


def _enforce_selection_plan_limit(
    plan_tier: Optional[str],
    selected_ids: list[str],
) -> None:
    limit = _channel_limit_for_plan_tier(plan_tier)
    if limit is not None and len(selected_ids) > limit:
        raise HTTPException(
            status_code=403,
            detail='selected channel limit exceeded for current plan',
        )


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


def _sanitize_archive_title(raw_title: Optional[str]) -> Optional[str]:
    if raw_title is None:
        return None
    title = raw_title.strip()[:MAX_CHANNEL_TITLE_LENGTH]
    return title or None


def _sanitize_archive_thumbnail_url(raw_url: Optional[str]) -> Optional[str]:
    if raw_url is None:
        return None
    url = raw_url.strip()[:MAX_CHANNEL_THUMBNAIL_LENGTH]
    return url or None


def _sanitize_archive_channel_id(
    raw_channel_id: Optional[str],
) -> Optional[str]:
    if raw_channel_id is None:
        return None
    channel_id = raw_channel_id.strip()
    if not channel_id:
        return None
    if not CHANNEL_ID_PATTERN.fullmatch(channel_id):
        return None
    return channel_id


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
    now = time.time()
    with GOOGLE_JWKS_LOCK:
        if (
            not force_refresh
            and GOOGLE_JWKS_BY_KID
            and GOOGLE_JWKS_STATE['expires_at'] > now
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
        GOOGLE_JWKS_STATE['expires_at'] = now + ttl
        return GOOGLE_JWKS_BY_KID


def _resolve_google_signing_key(token: str):
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=401,
            detail='invalid access token',
        ) from exc

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
    if _configured_client_ids and not audiences.intersection(
        _configured_client_ids
    ):
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
        raise HTTPException(
            status_code=401,
            detail='invalid access token',
        ) from exc

    subject = _validate_google_token_claims(payload)
    expires_at = payload.get('exp')
    try:
        expiry = float(expires_at)
    except (TypeError, ValueError) as exc:
        raise HTTPException(
            status_code=401,
            detail='token exp invalid',
        ) from exc

    with AUTH_CACHE_LOCK:
        AUTH_CACHE[token] = (expiry, subject)
        if len(AUTH_CACHE) > AUTH_CACHE_MAX_ITEMS:
            now_ts = time.time()
            expired_keys = [
                k for k, (exp, _) in AUTH_CACHE.items() if exp <= now_ts
            ]
            for k in expired_keys:
                AUTH_CACHE.pop(k, None)
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


def _resolve_transcript_principal(
    request: Request,
    authorization: Optional[str],
) -> str:
    if not BACKEND_REQUIRE_AUTH:
        return f'ip:{_resolve_client_id(request)}'
    token = _extract_bearer_token(authorization)
    user_id = _verify_google_user(token)
    return f'user:{user_id}'


def _has_trusted_plan_update_access(request: Request) -> bool:
    if ALLOW_CLIENT_PLAN_UPDATES:
        return True
    if not PLAN_UPDATE_SHARED_SECRET:
        return False
    provided = request.headers.get('x-plan-update-token', '').strip()
    return bool(provided) and hmac.compare_digest(
        provided,
        PLAN_UPDATE_SHARED_SECRET,
    )


_IP_PATTERN = re.compile(
    r'^(?:\d{1,3}\.){3}\d{1,3}$'          # IPv4
    r'|^[0-9a-fA-F:]{2,45}$'              # IPv6 (colon-hex, including ::)
)


def _resolve_client_id(request: Request) -> str:
    if TRUST_PROXY_HEADERS:
        forwarded = request.headers.get('x-forwarded-for', '')
        if forwarded:
            candidate = forwarded.split(',')[0].strip()
            if candidate and _IP_PATTERN.match(candidate):
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


def _enforce_write_rate_limit(
    request: Request,
    user_id: Optional[str] = None,
) -> None:
    principal = (
        f'user:{user_id}'
        if user_id
        else f'ip:{_resolve_client_id(request)}'
    )
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
    db_ok = check_db() if db_enabled else False
    schema_ok = False
    schema_detail = None
    if db_enabled and db_ok:
        schema_ok, schema_detail = validate_schema()
    return {
        'status': 'ok',
        'db_enabled': db_enabled,
        'db_ok': db_ok,
        'schema_ok': schema_ok,
        'schema_detail': schema_detail,
        'client_plan_management_enabled': ALLOW_CLIENT_PLAN_UPDATES,
    }


def _build_transcript_payload(
    source_text: str,
    *,
    source: str,
    summarize: bool,
    summary_lines: Optional[int],
    max_chars: int,
) -> dict[str, Any]:
    text, partial = trim_text(source_text, max_chars)
    summary = (
        transcript_utils.build_summary(
            source_text,
            summary_lines,
            api_key=OPENAI_API_KEY,
            input_chars=OPENAI_SUMMARY_INPUT_CHARS,
            model=OPENAI_SUMMARY_MODEL,
            max_tokens=OPENAI_SUMMARY_MAX_TOKENS,
        )
        if summarize
        else None
    )
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
    if transcript_utils.is_membership_error(error):
        return 'You might not have membership for this video.'
    if 'HTTP Error 403' in error or 'Forbidden' in error:
        return (
            '음성 다운로드가 차단되었습니다. '
            'YouTube 제한(로그인/연령/지역) 또는 다운로더 업데이트가 필요합니다.'
        )
    return detail


def _build_archive_metadata(
    req: ArchiveToggleRequest,
) -> dict[str, Optional[str]]:
    return {
        'title': _sanitize_archive_title(req.title),
        'thumbnail_url': _sanitize_archive_thumbnail_url(req.thumbnail_url),
        'channel_id': _sanitize_archive_channel_id(req.channel_id),
        'channel_title': _sanitize_archive_title(req.channel_title),
        'channel_thumbnail_url': _sanitize_archive_thumbnail_url(
            req.channel_thumbnail_url
        ),
    }


@app.post('/transcript')
def transcript(
    req: TranscriptRequest,
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    """Return transcript and summary for a YouTube video."""
    principal = _resolve_transcript_principal(request, authorization)
    _enforce_transcript_rate_limit(principal)
    video_id = _sanitize_video_id(req.video_id)
    max_chars = sanitize_max_chars(req.max_chars)
    cache_key = build_transcript_cache_key(
        video_id=video_id,
        max_chars=max_chars,
        summarize=bool(req.summarize),
        summary_lines=req.summary_lines,
    )

    cached = load_cache(cache_key)
    if cached:
        return {**cached, 'cached': True}

    with _transcript_slot(TRANSCRIPT_QUEUE_TIMEOUT):
        caption_text = transcript_utils.fetch_caption_text(video_id)
        if not caption_text:
            caption_text = transcript_utils.fetch_caption_text_via_ytdlp(
                video_id,
                cookies_from_browser=YTDLP_COOKIES_FROM_BROWSER,
                cookies_path=YTDLP_COOKIES_PATH,
                player_client_list=YTDLP_PLAYER_CLIENT_LIST,
                socket_timeout_seconds=YTDLP_SOCKET_TIMEOUT_SECONDS,
                youtube_dl_cls=YoutubeDL,
            )

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

        audio_path, error = transcript_utils.download_audio(
            video_id,
            cookies_from_browser=YTDLP_COOKIES_FROM_BROWSER,
            cookies_path=YTDLP_COOKIES_PATH,
            player_client_list=YTDLP_PLAYER_CLIENT_LIST,
            socket_timeout_seconds=YTDLP_SOCKET_TIMEOUT_SECONDS,
            youtube_dl_cls=YoutubeDL,
            download_error_cls=DownloadError,
        )
        if audio_path is None:
            raise HTTPException(
                status_code=500,
                detail=_resolve_audio_download_detail(error),
            )

        try:
            transcript_text = transcript_utils.transcribe_audio(
                audio_path, api_key=OPENAI_API_KEY,
            )
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
                archives = (
                    session.query(Archive)
                    .filter(Archive.user_id == user_id)
                    .order_by(Archive.archived_at.desc())
                    .all()
                )
                return {'items': serialize_archive_items(session, archives)}
        except SQLAlchemyError as exc:
            if FAIL_CLOSED_WITHOUT_DB:
                raise HTTPException(
                    status_code=503,
                    detail='database required',
                ) from exc
            return {'items': []}
    if not _allow_file_fallback():
        raise HTTPException(status_code=503, detail='database required')
    return {'items': load_archives_file(user_id)}


def _build_db_archive_response(
    session: Any,
    video_id: str,
    archive: Archive,
    metadata: dict[str, Optional[str]],
) -> dict[str, Any]:
    """Build an archive response dict from DB records."""
    video = session.query(Video).filter(Video.id == video_id).first()
    channel = (
        session.query(Channel).filter(Channel.id == video.channel_id).first()
        if video is not None
        else None
    )
    return {
        'archived': True,
        'video_id': video_id,
        'archived_at': int(archive.archived_at.timestamp() * 1000),
        'title': (
            video.title if video is not None
            else (metadata.get('title') or ARCHIVE_PLACEHOLDER_VIDEO_TITLE)
        ),
        'thumbnail_url': (
            video.thumbnail_url if video is not None
            else metadata.get('thumbnail_url')
        ),
        'channel_id': (
            video.channel_id if video is not None
            else (metadata.get('channel_id') or ARCHIVE_PLACEHOLDER_CHANNEL_ID)
        ),
        'channel_title': (
            channel.title if channel is not None
            else (
                metadata.get('channel_title')
                or ARCHIVE_PLACEHOLDER_CHANNEL_TITLE
            )
        ),
        'channel_thumbnail_url': (
            channel.thumbnail_url if channel is not None
            else metadata.get('channel_thumbnail_url')
        ),
    }


@app.post('/archives/toggle')
def toggle_archive(
    req: ArchiveToggleRequest,
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    """Set or toggle archive status for a video."""
    user_id = _authorize_user(req.user_id, authorization)
    _enforce_write_rate_limit(request, user_id)
    video_id = _sanitize_archive_video_id(req.video_id)
    metadata = _build_archive_metadata(req)
    _require_database_for_write()

    if is_db_enabled():
        try:
            with get_session() as session:
                if session is None:
                    _raise_db_unavailable()
                ensure_user_exists(session, user_id)
                existing = (
                    session.query(Archive)
                    .filter(
                        Archive.user_id == user_id,
                        Archive.video_id == video_id,
                    )
                    .first()
                )
                should_archive = (
                    req.archived
                    if req.archived is not None
                    else existing is None
                )
                if not should_archive:
                    if existing:
                        session.delete(existing)
                    session.commit()
                    return {'archived': False, 'video_id': video_id}

                upsert_archive_video(session, video_id, metadata)
                if existing is None:
                    existing = Archive(user_id=user_id, video_id=video_id)
                    session.add(existing)
                session.flush()
                result = _build_db_archive_response(
                    session, video_id, existing, metadata,
                )
                session.commit()
                return result
        except IntegrityError as exc:
            if req.archived is True:
                try:
                    with get_session() as session:
                        session = _require_session(session)
                        existing = (
                            session.query(Archive)
                            .filter(
                                Archive.user_id == user_id,
                                Archive.video_id == video_id,
                            )
                            .first()
                        )
                        if existing is not None:
                            return _build_db_archive_response(
                                session, video_id, existing, metadata,
                            )
                except SQLAlchemyError:
                    pass
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
    return toggle_archive_file(user_id, video_id, metadata, req.archived)


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
    save_archives_file(user_id, [])
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
    _require_database_for_write()
    if not is_db_enabled():
        return {
            'user_id': user_id,
            'email': email,
            'plan_tier': 'free',
        }
    try:
        with get_session() as session:
            if session is None:
                _raise_db_unavailable()
            user = upsert_user_profile(
                session,
                user_id=user_id,
                email=email,
            )
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
    if not _has_trusted_plan_update_access(request):
        raise HTTPException(
            status_code=403,
            detail='plan updates require trusted server credentials',
        )
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
            ensure_user_exists(session, user_id)
            upsert_user_state_row(
                session,
                user_id,
                selection_change_day=selection_change_day,
                selection_changes_today=selection_changes_today,
                opened_video_ids=opened_video_ids,
            )
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
            user = session.query(User).filter(User.id == user_id).first()
            rows = (
                session.query(UserChannel)
                .filter(
                    UserChannel.user_id == user_id,
                    UserChannel.is_selected.is_(True),
                )
                .order_by(UserChannel.channel_id.asc())
                .all()
            )
            selected_ids = [row.channel_id for row in rows]
            limit = _channel_limit_for_plan_tier(
                user.plan_tier if user is not None else 'free'
            )
            if limit is not None and len(selected_ids) > limit:
                selected_ids = selected_ids[:limit]
            return {'selected_ids': selected_ids}
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
    normalized_channels, selected_ids_sorted = normalize_selection_request(req)
    _require_database_for_write()
    if not is_db_enabled():
        _enforce_selection_plan_limit('free', selected_ids_sorted)
        return {'selected_ids': selected_ids_sorted}
    try:
        with get_session() as session:
            session = _require_session(session)
            ensure_user_exists(session, user_id)
            user = session.query(User).filter(User.id == user_id).first()
            _enforce_selection_plan_limit(
                user.plan_tier if user is not None else 'free',
                selected_ids_sorted,
            )
            upsert_channels(session, normalized_channels)
            sync_user_channel_links(session, user_id, selected_ids_sorted)

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


