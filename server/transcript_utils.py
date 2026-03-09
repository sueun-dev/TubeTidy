"""Transcript, caption, and file fallback helpers."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import time
from typing import Optional

import requests
from sqlalchemy.exc import SQLAlchemyError
from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError

from .config import (
    CACHE_DIR,
    CAPTION_FORMAT_PRIORITY,
    FAIL_CLOSED_WITHOUT_DB,
    OPENAI_SUMMARY_INPUT_CHARS,
    OPENAI_SUMMARY_MAX_TOKENS,
    OPENAI_SUMMARY_MODEL,
    TRANSCRIPT_CACHE_TTL,
    TRANSCRIPT_DEFAULT_MAX_CHARS,
    TRANSCRIPT_MAX_MAX_CHARS,
    TRANSCRIPT_MIN_MAX_CHARS,
    USER_AGENT,
    VIDEO_ID_PATTERN,
    YTDLP_COOKIES_FROM_BROWSER,
    YTDLP_COOKIES_PATH,
    YTDLP_PLAYER_CLIENT_LIST,
    YTDLP_SOCKET_TIMEOUT_SECONDS,
)
from .db import get_session, is_db_enabled
from .models import TranscriptCache

DEFAULT_HEADERS = {'User-Agent': USER_AGENT}


def _allow_file_fallback() -> bool:
    return not FAIL_CLOSED_WITHOUT_DB


def sanitize_max_chars(max_chars: Optional[int]) -> int:
    """Clamp transcript max_chars into the supported range."""
    if max_chars is None:
        return TRANSCRIPT_DEFAULT_MAX_CHARS
    return max(
        TRANSCRIPT_MIN_MAX_CHARS,
        min(TRANSCRIPT_MAX_MAX_CHARS, int(max_chars)),
    )


def trim_text(text: str, max_chars: Optional[int]) -> tuple[str, bool]:
    """Trim text to max_chars and return the partial flag."""
    if not max_chars or len(text) <= max_chars:
        return text, False
    return text[:max_chars].rstrip() + '…', True


def build_summary(
    text: str,
    lines: Optional[int],
    *,
    api_key: Optional[str],
    input_chars: int = OPENAI_SUMMARY_INPUT_CHARS,
    model: str = OPENAI_SUMMARY_MODEL,
    max_tokens: int = OPENAI_SUMMARY_MAX_TOKENS,
) -> Optional[str]:
    """Build a normalized summary for the given text."""
    if not text.strip() or not api_key:
        return None

    target_lines = max(1, min(5, lines or 3))
    summary_input = text
    if 0 < input_chars < len(summary_input):
        summary_input = summary_input[:input_chars]

    summary = summarize_text(
        summary_input,
        target_lines,
        api_key=api_key,
        model=model,
        max_tokens=max_tokens,
    )
    if not summary:
        return None
    return normalize_summary(summary, target_lines)


def summarize_text(
    text: str,
    lines: int,
    *,
    api_key: str,
    model: str,
    max_tokens: int,
) -> Optional[str]:
    """Call OpenAI to summarize the text into a fixed number of lines."""
    prompt = (
        f'다음 내용을 한국어로 {lines}줄 요약해줘.\\n'
        '- 각 줄은 한 문장\\n'
        "- 각 줄은 '• '로 시작\\n"
        f'- 줄바꿈으로만 {lines}줄 출력\\n'
        '- 과장 없이 핵심 사실만\\n\\n'
        f'{text}'
    )
    payload = {
        'model': model,
        'temperature': 0.2,
        'max_tokens': max_tokens,
        'messages': [
            {
                'role': 'system',
                'content': '너는 텍스트를 간결하게 요약하는 한국어 요약 전문가다.',
            },
            {'role': 'user', 'content': prompt},
        ],
    }
    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json',
    }

    try:
        response = requests.post(
            'https://api.openai.com/v1/chat/completions',
            headers=headers,
            json=payload,
            timeout=60,
        )
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


def build_transcript_cache_key(
    *,
    video_id: str,
    max_chars: int,
    summarize: bool,
    summary_lines: Optional[int],
) -> str:
    """Build a stable cache key per transcript request shape."""
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


def load_archives_file(user_id: str) -> list[dict]:
    """Load archive fallback data from the local cache directory."""
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
            items.append(
                {
                    'video_id': video_id,
                    'archived_at': archived_at,
                    'title': entry.get('title'),
                    'thumbnail_url': entry.get('thumbnail_url'),
                    'channel_id': entry.get('channel_id'),
                    'channel_title': entry.get('channel_title'),
                    'channel_thumbnail_url': entry.get('channel_thumbnail_url'),
                }
            )
    return items


def save_archives_file(user_id: str, items: list[dict]) -> None:
    """Persist archive fallback data to the local cache directory."""
    path = _archive_cache_path(user_id)
    try:
        path.write_text(json.dumps(items, ensure_ascii=False), encoding='utf-8')
    except OSError:
        pass


def toggle_archive_file(
    user_id: str,
    video_id: str,
    metadata: dict[str, Optional[str]],
    archived: Optional[bool],
) -> dict:
    """Toggle archive state when DB persistence is unavailable."""
    items = load_archives_file(user_id)
    existing_index = next(
        (
            idx
            for idx, entry in enumerate(items)
            if entry.get('video_id') == video_id
        ),
        None,
    )
    should_archive = (
        archived if archived is not None else existing_index is None
    )
    if not should_archive:
        if existing_index is not None:
            items.pop(existing_index)
            save_archives_file(user_id, items)
        return {'archived': False, 'video_id': video_id}

    if existing_index is not None:
        existing_entry = items[existing_index]
        archived_at = existing_entry.get('archived_at')
        if not isinstance(archived_at, int):
            archived_at = int(time.time() * 1000)
        items[existing_index] = {
            'video_id': video_id,
            'archived_at': archived_at,
            'title': metadata['title'] or existing_entry.get('title'),
            'thumbnail_url': (
                metadata['thumbnail_url'] or existing_entry.get('thumbnail_url')
            ),
            'channel_id': (
                metadata['channel_id'] or existing_entry.get('channel_id')
            ),
            'channel_title': (
                metadata['channel_title'] or existing_entry.get('channel_title')
            ),
            'channel_thumbnail_url': (
                metadata['channel_thumbnail_url']
                or existing_entry.get('channel_thumbnail_url')
            ),
        }
        save_archives_file(user_id, items)
        return {
            'archived': True,
            'video_id': video_id,
            'archived_at': archived_at,
            'title': items[existing_index].get('title'),
            'thumbnail_url': items[existing_index].get('thumbnail_url'),
            'channel_id': items[existing_index].get('channel_id'),
            'channel_title': items[existing_index].get('channel_title'),
            'channel_thumbnail_url': items[existing_index].get(
                'channel_thumbnail_url'
            ),
        }

    archived_at = int(time.time() * 1000)
    items.append(
        {
            'video_id': video_id,
            'archived_at': archived_at,
            'title': metadata['title'],
            'thumbnail_url': metadata['thumbnail_url'],
            'channel_id': metadata['channel_id'],
            'channel_title': metadata['channel_title'],
            'channel_thumbnail_url': metadata['channel_thumbnail_url'],
        }
    )
    save_archives_file(user_id, items)
    return {
        'archived': True,
        'video_id': video_id,
        'archived_at': archived_at,
        'title': metadata['title'],
        'thumbnail_url': metadata['thumbnail_url'],
        'channel_id': metadata['channel_id'],
        'channel_title': metadata['channel_title'],
        'channel_thumbnail_url': metadata['channel_thumbnail_url'],
    }


def fetch_caption_text(video_id: str) -> Optional[str]:
    """Fetch captions via timedtext API for a video."""
    tracks = fetch_caption_tracks(video_id)
    track = pick_track(tracks)
    if not track:
        return None

    text = download_caption_text(video_id, track)
    return text if text else None


def fetch_caption_text_via_ytdlp(
    video_id: str,
    *,
    cookies_from_browser: Optional[str] = YTDLP_COOKIES_FROM_BROWSER,
    cookies_path: Optional[str] = YTDLP_COOKIES_PATH,
    player_client_list: tuple[str, ...] = YTDLP_PLAYER_CLIENT_LIST,
    socket_timeout_seconds: int = YTDLP_SOCKET_TIMEOUT_SECONDS,
    youtube_dl_cls: type[YoutubeDL] = YoutubeDL,
) -> Optional[str]:
    """Fetch captions via yt-dlp extraction."""
    info = fetch_ytdlp_info(
        video_id,
        cookies_from_browser=cookies_from_browser,
        cookies_path=cookies_path,
        player_client_list=player_client_list,
        socket_timeout_seconds=socket_timeout_seconds,
        youtube_dl_cls=youtube_dl_cls,
    )
    if not info and not cookies_from_browser:
        info = fetch_ytdlp_info(
            video_id,
            cookies_from_browser='chrome',
            cookies_path=cookies_path,
            player_client_list=player_client_list,
            socket_timeout_seconds=socket_timeout_seconds,
            youtube_dl_cls=youtube_dl_cls,
        )
    if not info and not cookies_from_browser:
        info = fetch_ytdlp_info(
            video_id,
            cookies_from_browser='safari',
            cookies_path=cookies_path,
            player_client_list=player_client_list,
            socket_timeout_seconds=socket_timeout_seconds,
            youtube_dl_cls=youtube_dl_cls,
        )
    if not info:
        return None

    subtitles = info.get('subtitles') or {}
    auto_captions = info.get('automatic_captions') or {}
    preferred = pick_lang_entries(subtitles) or pick_lang_entries(auto_captions)
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
    *,
    cookies_from_browser: Optional[str] = YTDLP_COOKIES_FROM_BROWSER,
    cookies_path: Optional[str] = YTDLP_COOKIES_PATH,
    player_client_list: tuple[str, ...] = YTDLP_PLAYER_CLIENT_LIST,
    socket_timeout_seconds: int = YTDLP_SOCKET_TIMEOUT_SECONDS,
    youtube_dl_cls: type[YoutubeDL] = YoutubeDL,
) -> Optional[dict]:
    """Retrieve yt-dlp metadata for a video."""
    ydl_opts = {
        'quiet': True,
        'skip_download': True,
        'writesubtitles': True,
        'writeautomaticsub': True,
        'subtitleslangs': ['ko', 'en'],
        'geo_bypass': True,
        'socket_timeout': socket_timeout_seconds,
        'extractor_args': {
            'youtube': {
                'player_client': list(player_client_list) or ['android', 'web'],
            }
        },
    }
    if cookies_path:
        ydl_opts['cookiefile'] = cookies_path
    if cookies_from_browser:
        ydl_opts['cookiesfrombrowser'] = (cookies_from_browser,)

    try:
        with youtube_dl_cls(ydl_opts) as ydl:
            return ydl.extract_info(
                f'https://www.youtube.com/watch?v={video_id}',
                download=False,
            )
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
    try:
        response = requests.get(
            'https://www.youtube.com/api/timedtext',
            params={'type': 'list', 'v': video_id},
            headers=DEFAULT_HEADERS,
            timeout=10,
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

    def pick(prefix: str) -> Optional[dict]:
        for track in tracks:
            if track['lang'].lower().startswith(prefix):
                return track
        return None

    return pick('ko') or pick('en') or tracks[0]


def download_caption_text(video_id: str, track: dict) -> Optional[str]:
    """Download and parse caption text for a specific track."""
    formats = ['vtt', 'json3', 'srv3', 'ttml', None]

    for fmt in formats:
        params = {'v': video_id, 'lang': track['lang']}
        if fmt:
            params['fmt'] = fmt
        if track.get('kind'):
            params['kind'] = track['kind']

        try:
            response = requests.get(
                'https://www.youtube.com/api/timedtext',
                params=params,
                headers=DEFAULT_HEADERS,
                timeout=10,
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
    buffer = []
    for line in raw.splitlines():
        trimmed = line.strip()
        if not trimmed or trimmed == 'WEBVTT':
            continue
        if '-->' in trimmed or re.match(r'^\d+$', trimmed):
            continue
        cleaned = re.sub(r'<[^>]+>', '', trimmed)
        if cleaned:
            buffer.append(cleaned)
    return ' '.join(buffer).strip()


def download_caption_payload(url: str, ext: Optional[str]) -> Optional[str]:
    """Download caption payload and parse it based on format."""
    try_urls = [url]
    if 'fmt=' not in url:
        joiner = '&' if '?' in url else '?'
        try_urls.append(f'{url}{joiner}fmt=vtt')

    for target in try_urls:
        try:
            response = requests.get(
                target,
                headers=DEFAULT_HEADERS,
                timeout=10,
            )
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


def download_audio(
    video_id: str,
    *,
    cookies_from_browser: Optional[str] = YTDLP_COOKIES_FROM_BROWSER,
    cookies_path: Optional[str] = YTDLP_COOKIES_PATH,
    player_client_list: tuple[str, ...] = YTDLP_PLAYER_CLIENT_LIST,
    socket_timeout_seconds: int = YTDLP_SOCKET_TIMEOUT_SECONDS,
    youtube_dl_cls: type[YoutubeDL] = YoutubeDL,
    download_error_cls: type[DownloadError] = DownloadError,
) -> tuple[Optional[str], Optional[str]]:
    """Download audio for a video and return the local path plus error."""
    with tempfile.TemporaryDirectory() as tmpdir:
        output = os.path.join(tmpdir, f'{video_id}.%(ext)s')
        ydl_opts = {
            'format': 'bestaudio[ext=m4a]/bestaudio/best',
            'outtmpl': output,
            'quiet': True,
            'noplaylist': True,
            'geo_bypass': True,
            'socket_timeout': socket_timeout_seconds,
            'extractor_args': {
                'youtube': {
                    'player_client': (
                        list(player_client_list) or ['android', 'web']
                    ),
                }
            },
        }
        if cookies_path:
            ydl_opts['cookiefile'] = cookies_path
        if cookies_from_browser:
            ydl_opts['cookiesfrombrowser'] = (cookies_from_browser,)
        try:
            with youtube_dl_cls(ydl_opts) as ydl:
                ydl.extract_info(
                    f'https://www.youtube.com/watch?v={video_id}',
                    download=True,
                )
        except download_error_cls as error:
            if cookies_from_browser:
                return None, str(error)
            try:
                with youtube_dl_cls(
                    {**ydl_opts, 'cookiesfrombrowser': ('chrome',)}
                ) as ydl:
                    ydl.extract_info(
                        f'https://www.youtube.com/watch?v={video_id}',
                        download=True,
                    )
            except Exception as retry_error:
                return None, str(retry_error)
        except Exception as error:
            return None, str(error)

        files = list(Path(tmpdir).glob(f'{video_id}.*'))
        if not files:
            return None, '음성 파일을 찾지 못했습니다.'
        source = files[0]
        fd, temp_name = tempfile.mkstemp(
            prefix='youtube-summary-audio-',
            suffix=source.suffix,
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
        "available to this channel's members",
        'only available to channel members',
    ]
    return any(keyword in lowered for keyword in keywords)


def transcribe_audio(path: str, *, api_key: Optional[str]) -> Optional[str]:
    """Transcribe audio using OpenAI Whisper API."""
    if not api_key:
        return None
    headers = {'Authorization': f'Bearer {api_key}'}
    with open(path, 'rb') as audio_file:
        files = {'file': audio_file}
        data = {'model': 'whisper-1', 'response_format': 'json'}
        try:
            response = requests.post(
                'https://api.openai.com/v1/audio/transcriptions',
                headers=headers,
                files=files,
                data=data,
                timeout=120,
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
            json.dumps(data, ensure_ascii=False),
            encoding='utf-8',
        )
        temp_path.replace(path)
    except OSError:
        pass


def _archive_cache_path(user_id: str) -> Path:
    safe = re.sub(r'[^a-zA-Z0-9_-]+', '_', user_id)
    return CACHE_DIR / f'archive_{safe}.json'
