"""Backend configuration and immutable runtime constants."""

from pathlib import Path
import os
import re
from typing import Optional

from dotenv import load_dotenv

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
YTDLP_SOCKET_TIMEOUT_SECONDS = max(
    1,
    int(os.getenv('YTDLP_SOCKET_TIMEOUT_SECONDS', '10')),
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
ALLOW_CLIENT_PLAN_UPDATES = _env_flag('ALLOW_CLIENT_PLAN_UPDATES', False)
PLAN_UPDATE_SHARED_SECRET = os.getenv('PLAN_UPDATE_SHARED_SECRET', '').strip()
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
CONFIGURED_CLIENT_IDS = frozenset(
    value.strip()
    for value in (
        os.getenv('GOOGLE_CLIENT_IDS', '').split(',')
        + [
            os.getenv('GOOGLE_WEB_CLIENT_ID', ''),
            os.getenv('GOOGLE_IOS_CLIENT_ID', ''),
        ]
    )
    if value and value.strip()
)

CACHE_DIR = ROOT / 'server' / 'cache'
CACHE_DIR.mkdir(parents=True, exist_ok=True)
VIDEO_ID_PATTERN = re.compile(r'^[A-Za-z0-9_-]{6,32}$')
ARCHIVE_VIDEO_ID_PATTERN = re.compile(r'^[A-Za-z0-9_-]{6,64}$')
USER_ID_PATTERN = re.compile(r'^[A-Za-z0-9._:-]{3,128}$')
CHANNEL_ID_PATTERN = re.compile(r'^[A-Za-z0-9_-]{3,64}$')
PLAN_TIER_PATTERN = re.compile(r'^(free|starter|growth|unlimited|lifetime)$')
PLAN_CHANNEL_LIMITS: dict[str, Optional[int]] = {
    'free': 3,
    'starter': 10,
    'growth': 50,
    'unlimited': None,
    'lifetime': None,
}
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
WRITE_RATE_LIMIT_PER_WINDOW = int(
    os.getenv('WRITE_RATE_LIMIT_PER_WINDOW', '60')
)
WRITE_RATE_LIMIT_WINDOW_SECONDS = int(
    os.getenv('WRITE_RATE_LIMIT_WINDOW_SECONDS', '60')
)
RATE_LIMIT_MAX_BUCKETS = int(os.getenv('RATE_LIMIT_MAX_BUCKETS', '8192'))
GOOGLE_JWKS_ISSUERS = (
    'accounts.google.com',
    'https://accounts.google.com',
)
CAPTION_FORMAT_PRIORITY = {
    'vtt': 0,
    'json3': 1,
    'srv3': 2,
    'srv2': 3,
    'srv1': 4,
    'ttml': 5,
    'xml': 6,
}
