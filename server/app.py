import html
import json
import os
import re
import tempfile
import threading
import time
from pathlib import Path
from typing import Optional

import requests
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env')

OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
OPENAI_SUMMARY_MODEL = os.getenv('OPENAI_SUMMARY_MODEL', 'gpt-4o-mini')
OPENAI_SUMMARY_INPUT_CHARS = int(os.getenv('OPENAI_SUMMARY_INPUT_CHARS', '4000'))
OPENAI_SUMMARY_MAX_TOKENS = int(os.getenv('OPENAI_SUMMARY_MAX_TOKENS', '200'))
YTDLP_COOKIES_PATH = os.getenv('YTDLP_COOKIES_PATH')
YTDLP_COOKIES_FROM_BROWSER = os.getenv('YTDLP_COOKIES_FROM_BROWSER')
YTDLP_PLAYER_CLIENTS = os.getenv('YTDLP_PLAYER_CLIENTS', 'android,web,ios,tv,web_embedded')
TRANSCRIPT_CACHE_TTL = int(os.getenv('TRANSCRIPT_CACHE_TTL', '86400'))
TRANSCRIPT_MAX_CONCURRENCY = int(os.getenv('TRANSCRIPT_MAX_CONCURRENCY', '2'))
TRANSCRIPT_QUEUE_TIMEOUT = int(os.getenv('TRANSCRIPT_QUEUE_TIMEOUT', '20'))
USER_AGENT = os.getenv(
    'YTDLP_USER_AGENT',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
)

CACHE_DIR = ROOT / 'server' / 'cache'
CACHE_DIR.mkdir(parents=True, exist_ok=True)
TRANSCRIPT_SEMAPHORE = threading.Semaphore(max(1, TRANSCRIPT_MAX_CONCURRENCY))
DEFAULT_HEADERS = {'User-Agent': USER_AGENT}

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        'http://localhost:5201',
        'http://127.0.0.1:5201',
    ],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)


class TranscriptRequest(BaseModel):
    video_id: str
    max_chars: Optional[int] = 1200
    summarize: Optional[bool] = True
    summary_lines: Optional[int] = 3


@app.post('/transcript')
def transcript(req: TranscriptRequest):
    video_id = req.video_id.strip()
    if not video_id:
        raise HTTPException(status_code=400, detail='video_id is required')

    cached = load_cache(video_id)
    if cached:
        return {**cached, 'cached': True}

    if not TRANSCRIPT_SEMAPHORE.acquire(timeout=TRANSCRIPT_QUEUE_TIMEOUT):
        raise HTTPException(status_code=429, detail='요청이 많아 잠시 후 다시 시도해주세요.')

    try:
        caption_text = fetch_caption_text(video_id)
        if not caption_text:
            caption_text = fetch_caption_text_via_ytdlp(video_id)

        if caption_text:
            text, partial = trim_text(caption_text, req.max_chars)
            summary = build_summary(caption_text, req.summary_lines) if req.summarize else None
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
                if 'HTTP Error 403' in error or 'Forbidden' in error:
                    detail = (
                        '음성 다운로드가 차단되었습니다. '
                        'YouTube 제한(로그인/연령/지역) 또는 다운로더 업데이트가 필요합니다.'
                    )
                else:
                    detail = f'음성 다운로드에 실패했습니다. ({error})'
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

        text, partial = trim_text(transcript_text, req.max_chars)
        summary = build_summary(transcript_text, req.summary_lines) if req.summarize else None
        payload = {
            'text': text,
            'summary': summary,
            'source': 'whisper',
            'partial': partial,
        }
        save_cache(video_id, payload)
        return {**payload, 'cached': False}
    finally:
        TRANSCRIPT_SEMAPHORE.release()


def trim_text(text: str, max_chars: Optional[int]) -> tuple[str, bool]:
    if not max_chars or len(text) <= max_chars:
        return text, False
    return text[:max_chars].rstrip() + '…', True


def build_summary(text: str, lines: Optional[int]) -> Optional[str]:
    if not text.strip():
        return None
    if not OPENAI_API_KEY:
        return None

    target_lines = max(1, min(5, lines or 3))
    summary_input = text
    if OPENAI_SUMMARY_INPUT_CHARS > 0 and len(summary_input) > OPENAI_SUMMARY_INPUT_CHARS:
        summary_input = summary_input[:OPENAI_SUMMARY_INPUT_CHARS]

    summary = summarize_text(summary_input, target_lines)
    if not summary:
        return None
    return normalize_summary(summary, target_lines)


def summarize_text(text: str, lines: int) -> Optional[str]:
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

    data = response.json()
    choices = data.get('choices') or []
    if not choices:
        return None
    message = choices[0].get('message') or {}
    content = message.get('content')
    return content if isinstance(content, str) else None


def normalize_summary(summary: str, lines: int) -> str:
    normalized = summary.replace('\\\\n', '\n').replace('\\n', '\n')
    raw_lines = [line.strip() for line in normalized.splitlines() if line.strip()]
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
    path = CACHE_DIR / f'{video_id}.json'
    if not path.exists():
        return None

    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return None

    created_at = data.get('created_at')
    if created_at and (time.time() - created_at) > TRANSCRIPT_CACHE_TTL:
        return None

    return {
        'text': data.get('text', ''),
        'summary': data.get('summary'),
        'source': data.get('source', 'captions'),
        'partial': data.get('partial', False),
    }


def save_cache(video_id: str, payload: dict) -> None:
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
        temp_path.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
        temp_path.replace(path)
    except OSError:
        pass


def fetch_caption_text(video_id: str) -> Optional[str]:
    tracks = fetch_caption_tracks(video_id)
    track = pick_track(tracks)
    if not track:
        return None

    text = download_caption_text(video_id, track)
    return text if text else None


def fetch_caption_text_via_ytdlp(video_id: str) -> Optional[str]:
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


def fetch_ytdlp_info(video_id: str, cookies_from_browser: Optional[str] = None) -> Optional[dict]:
    url = f'https://www.youtube.com/watch?v={video_id}'
    player_clients = [c.strip() for c in YTDLP_PLAYER_CLIENTS.split(',') if c.strip()]
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
    order = ['vtt', 'json3', 'srv3', 'srv2', 'srv1', 'ttml', 'xml']

    def score(entry: dict) -> int:
        ext = (entry.get('ext') or '').lower()
        return order.index(ext) if ext in order else len(order)

    return sorted(entries, key=score)


def fetch_caption_tracks(video_id: str) -> list[dict]:
    url = 'https://www.youtube.com/api/timedtext'
    params = {'type': 'list', 'v': video_id}
    response = requests.get(url, params=params, headers=DEFAULT_HEADERS, timeout=10)
    if response.status_code != 200 or not response.text:
        return []

    tracks = []
    for match in re.finditer(r'<track ([^>]+)/?>', response.text):
        attrs = match.group(1)
        lang_match = re.search(r'lang_code="([^"]+)"', attrs)
        kind_match = re.search(r'kind="([^"]+)"', attrs)
        if not lang_match:
            continue
        tracks.append({'lang': lang_match.group(1), 'kind': kind_match.group(1) if kind_match else None})
    return tracks


def pick_track(tracks: list[dict]) -> Optional[dict]:
    if not tracks:
        return None

    def pick(prefix: str):
        for track in tracks:
            if track['lang'].lower().startswith(prefix):
                return track
        return None

    return pick('ko') or pick('en') or tracks[0]


def download_caption_text(video_id: str, track: dict) -> Optional[str]:
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

        response = requests.get(url, params=params, headers=DEFAULT_HEADERS, timeout=10)
        if response.status_code != 200 or not response.text:
            continue
        parsed = parse_caption_payload(response.text, fmt)
        if parsed:
            return parsed
    return None


def parse_vtt(raw: str) -> str:
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
    url = f'https://www.youtube.com/watch?v={video_id}'
    with tempfile.TemporaryDirectory() as tmpdir:
        output = os.path.join(tmpdir, f'{video_id}.%(ext)s')
        player_clients = [c.strip() for c in YTDLP_PLAYER_CLIENTS.split(',') if c.strip()]
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
                    with YoutubeDL({**ydl_opts, 'cookiesfrombrowser': ('chrome',)}) as ydl:
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
        temp_output = Path(tempfile.gettempdir()) / source.name
        temp_output.write_bytes(source.read_bytes())
        return str(temp_output), None


def transcribe_audio(path: str) -> Optional[str]:
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
        response = requests.post(url, headers=headers, files=files, data=data, timeout=120)

    if response.status_code != 200:
        return None

    payload = response.json()
    return payload.get('text')
