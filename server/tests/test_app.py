"""Unit tests for basic FastAPI behaviors and utilities."""

import os
import unittest

from fastapi.testclient import TestClient

os.environ.setdefault('BACKEND_REQUIRE_AUTH', 'false')

from server.app import _sanitize_max_chars, app, normalize_summary, trim_text


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


if __name__ == '__main__':
    unittest.main()
