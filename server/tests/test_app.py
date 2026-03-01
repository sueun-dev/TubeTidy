"""Unit tests for basic FastAPI behaviors and utilities."""

import os
from pathlib import Path
import threading
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

os.environ.setdefault('BACKEND_REQUIRE_AUTH', 'false')

import server.app as backend
from server.app import (
    _build_transcript_cache_key,
    _sanitize_max_chars,
    app,
    normalize_summary,
    trim_text,
)


class AppTestCase(unittest.TestCase):
    """Test basic API endpoints and helper utilities."""
    def setUp(self) -> None:
        self.client = TestClient(app)

    def test_root(self) -> None:
        """Ensure the root endpoint returns metadata."""
        response = self.client.get('/')
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertIn('name', payload)
        self.assertIn('version', payload)

    def test_health(self) -> None:
        """Ensure the health endpoint returns expected fields."""
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertIn('status', payload)
        self.assertIn('db_enabled', payload)

    def test_trim_text(self) -> None:
        """Trimmed text should include ellipsis and mark partial."""
        text, partial = trim_text('hello world', 5)
        self.assertEqual(text, 'hello…')
        self.assertTrue(partial)

    def test_sanitize_max_chars_clamps_bounds(self) -> None:
        """Max chars should be clamped to safe bounds."""
        self.assertEqual(_sanitize_max_chars(100), 300)
        self.assertEqual(_sanitize_max_chars(1200), 1200)
        self.assertEqual(_sanitize_max_chars(99999), 10000)

    def test_transcript_rejects_invalid_video_id(self) -> None:
        """Invalid video IDs should fail fast before external calls."""
        response = self.client.post('/transcript', json={'video_id': '../bad'})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json().get('detail'), 'video_id is invalid')

    def test_normalize_summary_lines(self) -> None:
        """Normalize summary to a fixed number of lines."""
        summary = '• 첫 번째 줄\\n• 두 번째 줄\\n• 세 번째 줄'
        normalized = normalize_summary(summary, 2)
        self.assertEqual(normalized.splitlines(), ['첫 번째 줄', '두 번째 줄'])

    def test_normalize_summary_strips_numeric_bullets(self) -> None:
        """Numeric bullets and whitespace should be removed reliably."""
        summary = '1. 첫 줄\n2. 둘째 줄\n3. 셋째 줄'
        normalized = normalize_summary(summary, 2)
        self.assertEqual(normalized.splitlines(), ['첫 줄', '둘째 줄'])

    def test_transcript_cache_key_depends_on_request_shape(self) -> None:
        """Cache key must vary by summary and max_chars options."""
        base = _build_transcript_cache_key(
            video_id='abc12345xyz',
            max_chars=1200,
            summarize=True,
            summary_lines=3,
        )
        no_summary = _build_transcript_cache_key(
            video_id='abc12345xyz',
            max_chars=1200,
            summarize=False,
            summary_lines=3,
        )
        shorter = _build_transcript_cache_key(
            video_id='abc12345xyz',
            max_chars=800,
            summarize=True,
            summary_lines=3,
        )
        self.assertNotEqual(base, no_summary)
        self.assertNotEqual(base, shorter)

    def test_parse_json3_tolerates_non_dict_events(self) -> None:
        """JSON3 parser should ignore malformed entries without raising."""
        raw = (
            '{"events":['
            '{"segs":[{"utf8":"hello "},null,{"utf8":"world"}]},'
            '"bad-event",'
            '{"segs":"invalid"},'
            '{"segs":[{"utf8":123},{"utf8":"!"}]}'
            ']}'
        )
        parsed = backend.parse_json3(raw)
        self.assertEqual(parsed, 'hello world!')

    def test_download_audio_retry_success_returns_audio_path(self) -> None:
        """Retry via chrome cookies should succeed instead of returning first error."""

        class _FakeYoutubeDL:
            attempts = 0

            def __init__(self, opts):
                self._opts = opts

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def extract_info(self, _url, download=False):
                _FakeYoutubeDL.attempts += 1
                if _FakeYoutubeDL.attempts == 1:
                    raise backend.DownloadError('first attempt failed')
                outtmpl = self._opts['outtmpl']
                output_path = Path(outtmpl.replace('%(ext)s', 'm4a'))
                output_path.write_text('audio', encoding='utf-8')
                return {'id': 'abc12345xyz'}

        with patch.object(backend, 'YTDLP_COOKIES_FROM_BROWSER', None):
            with patch.object(backend, 'YTDLP_COOKIES_PATH', None):
                with patch('server.app.YoutubeDL', _FakeYoutubeDL):
                    audio_path, error = backend.download_audio('abc12345xyz')

        self.assertIsNone(error)
        self.assertIsNotNone(audio_path)
        self.assertEqual(_FakeYoutubeDL.attempts, 2)
        if audio_path is not None and os.path.exists(audio_path):
            os.remove(audio_path)

    def test_selection_rejects_oversized_payload(self) -> None:
        """Selection payload size should be capped to prevent abuse."""
        channels = [
            {'id': f'ch{i:03d}', 'title': f'Channel {i}'}
            for i in range(0, 220)
        ]
        response = self.client.post(
            '/selection',
            json={
                'user_id': 'user_1234',
                'channels': channels,
                'selected_ids': ['ch000'],
            },
        )
        self.assertEqual(response.status_code, 413)

    def test_user_requires_valid_id(self) -> None:
        """User ID should fail with invalid format."""
        response = self.client.get('/user', params={'user_id': 'bad id'})
        self.assertEqual(response.status_code, 400)

    def test_archive_toggle_requires_valid_video_id(self) -> None:
        """Archive toggle should validate video_id format."""
        response = self.client.post(
            '/archives/toggle',
            json={'user_id': 'user_1234', 'video_id': '../bad'},
        )
        self.assertEqual(response.status_code, 400)

    def test_user_state_defaults_without_db(self) -> None:
        """User state endpoint should return sane defaults when DB is disabled."""
        response = self.client.get('/user/state', params={'user_id': 'user_1234'})
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body.get('selection_change_day'), 0)
        self.assertEqual(body.get('selection_changes_today'), 0)
        self.assertEqual(body.get('opened_video_ids'), [])

    def test_cors_allows_localhost_5301_preflight(self) -> None:
        """Default CORS should include local web dev port 5301."""
        response = self.client.options(
            '/user/upsert',
            headers={
                'Origin': 'http://localhost:5301',
                'Access-Control-Request-Method': 'POST',
            },
        )
        self.assertLess(response.status_code, 400)
        self.assertEqual(
            response.headers.get('access-control-allow-origin'),
            'http://localhost:5301',
        )

    def test_transcript_returns_429_when_queue_slot_unavailable(self) -> None:
        """Transcript endpoint should fail fast when all slots are occupied."""
        with patch.object(backend, 'TRANSCRIPT_SEMAPHORE', threading.Semaphore(1)):
            with patch.object(backend, 'TRANSCRIPT_QUEUE_TIMEOUT', 0):
                acquired = backend.TRANSCRIPT_SEMAPHORE.acquire(blocking=False)
                self.assertTrue(acquired)
                try:
                    response = self.client.post(
                        '/transcript',
                        json={'video_id': 'abc12345xyz'},
                    )
                finally:
                    backend.TRANSCRIPT_SEMAPHORE.release()
        self.assertEqual(response.status_code, 429)
        self.assertIn('요청이 많아', response.json().get('detail', ''))

    def test_transcript_releases_slot_after_failure(self) -> None:
        """Semaphore slot should be released even when transcript fails."""
        with patch.object(backend, 'TRANSCRIPT_SEMAPHORE', threading.Semaphore(1)):
            with patch.object(backend, 'TRANSCRIPT_QUEUE_TIMEOUT', 0):
                with patch.object(backend, 'OPENAI_API_KEY', None):
                    with patch('server.app.fetch_caption_text', return_value=None):
                        with patch(
                            'server.app.fetch_caption_text_via_ytdlp',
                            return_value=None,
                        ):
                            response = self.client.post(
                                '/transcript',
                                json={'video_id': 'abc12345xyz'},
                            )
        self.assertEqual(response.status_code, 400)
        acquired = backend.TRANSCRIPT_SEMAPHORE.acquire(blocking=False)
        self.assertTrue(acquired)
        if acquired:
            backend.TRANSCRIPT_SEMAPHORE.release()

    def test_auth_required_without_bearer_token_returns_401(self) -> None:
        """Protected endpoints should reject requests without bearer token."""
        with patch.object(backend, 'BACKEND_REQUIRE_AUTH', True):
            response = self.client.get('/selection', params={'user_id': 'user_1234'})
        self.assertEqual(response.status_code, 401)
        self.assertEqual(
            response.json().get('detail'),
            'authorization is required',
        )

    def test_auth_rejects_invalid_access_token(self) -> None:
        """Protected endpoints should reject invalid access tokens."""
        with patch.object(backend, 'BACKEND_REQUIRE_AUTH', True):
            with patch(
                'server.app._verify_google_user',
                side_effect=backend.HTTPException(
                    status_code=401,
                    detail='invalid access token',
                ),
            ):
                response = self.client.get(
                    '/selection',
                    params={'user_id': 'user_1234'},
                    headers={'Authorization': 'Bearer bad-token'},
                )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json().get('detail'), 'invalid access token')

    def test_auth_rejects_user_mismatch(self) -> None:
        """Protected endpoints should reject token/user mismatches."""
        with patch.object(backend, 'BACKEND_REQUIRE_AUTH', True):
            with patch('server.app._verify_google_user', return_value='user_other'):
                response = self.client.get(
                    '/selection',
                    params={'user_id': 'user_1234'},
                    headers={'Authorization': 'Bearer sample-token'},
                )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json().get('detail'), 'user mismatch')

    def test_write_rate_limit_rejects_burst_requests(self) -> None:
        """Write endpoints should enforce per-principal burst limits."""
        with patch.object(backend, 'WRITE_RATE_LIMIT_PER_WINDOW', 1):
            with patch.object(backend, 'WRITE_RATE_LIMIT_WINDOW_SECONDS', 60):
                with patch('server.app.is_db_enabled', return_value=False):
                    with backend.WRITE_RATE_LOCK:
                        backend.WRITE_RATE_BUCKETS.clear()
                    first = self.client.post(
                        '/user/upsert',
                        json={'user_id': 'user_1234'},
                    )
                    second = self.client.post(
                        '/user/upsert',
                        json={'user_id': 'user_1234'},
                    )
        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 429)
        self.assertIn('요청이 많아', second.json().get('detail', ''))

    def test_fail_closed_mode_rejects_writes_without_db(self) -> None:
        """Strict mode should fail closed when DB is unavailable."""
        with patch.object(backend, 'FAIL_CLOSED_WITHOUT_DB', True):
            with patch('server.app.is_db_enabled', return_value=False):
                response = self.client.post(
                    '/user/upsert',
                    json={'user_id': 'user_1234'},
                )
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json().get('detail'), 'database required')

    def test_google_claim_validation_requires_azp_for_multi_aud(self) -> None:
        """Multi-audience tokens should include a valid azp claim."""
        payload = {
            'iss': 'https://accounts.google.com',
            'aud': ['client_a', 'client_b'],
            'sub': 'user_1234',
        }
        with patch.object(backend, '_configured_client_ids', {'client_a'}):
            with self.assertRaises(backend.HTTPException) as exc_context:
                backend._validate_google_token_claims(payload)
        self.assertEqual(exc_context.exception.status_code, 401)
        self.assertEqual(exc_context.exception.detail, 'token azp missing')


if __name__ == '__main__':
    unittest.main()
