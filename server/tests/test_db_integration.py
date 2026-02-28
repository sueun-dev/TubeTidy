"""Database integration tests for the FastAPI backend."""

import importlib
import os
from concurrent.futures import ThreadPoolExecutor
import threading
import unittest
import uuid
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError


def _with_schema(database_url: str, schema: str) -> str:
    parsed = urlparse(database_url)
    query = parse_qs(parsed.query)
    query['options'] = [f'-csearch_path={schema}']
    return urlunparse(parsed._replace(query=urlencode(query, doseq=True)))


class DatabaseIntegrationTest(unittest.TestCase):
    """Verify database-backed endpoints using a real schema."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.base_database_url = os.getenv('DATABASE_URL')
        if not cls.base_database_url:
            raise unittest.SkipTest(
                'DATABASE_URL is not set. Skipping DB integration tests.'
            )

        cls.schema = f'test_schema_{uuid.uuid4().hex}'
        cls.schema_url = _with_schema(cls.base_database_url, cls.schema)

        engine = create_engine(cls.base_database_url)
        try:
            with engine.connect() as conn:
                conn.execute(text(f'CREATE SCHEMA "{cls.schema}"'))
                conn.commit()
        except OperationalError as exc:
            raise unittest.SkipTest(
                'PostgreSQL is unavailable for DB integration tests: '
                f'{exc.__class__.__name__}'
            ) from exc
        finally:
            engine.dispose()

        cls.previous_require_auth = os.getenv('BACKEND_REQUIRE_AUTH')
        os.environ['BACKEND_REQUIRE_AUTH'] = 'false'
        os.environ['DATABASE_URL'] = cls.schema_url
        import server.db as db
        import server.app as app

        importlib.reload(db)
        importlib.reload(app)
        db.init_db()

        cls.client = TestClient(app.app)

    @classmethod
    def tearDownClass(cls) -> None:
        try:
            engine = create_engine(cls.base_database_url)
            with engine.connect() as conn:
                conn.execute(
                    text(f'DROP SCHEMA IF EXISTS "{cls.schema}" CASCADE')
                )
                conn.commit()
            engine.dispose()
        finally:
            if cls.previous_require_auth is None:
                os.environ.pop('BACKEND_REQUIRE_AUTH', None)
            else:
                os.environ['BACKEND_REQUIRE_AUTH'] = cls.previous_require_auth
            if cls.base_database_url:
                os.environ['DATABASE_URL'] = cls.base_database_url
            if hasattr(cls, 'client'):
                cls.client.close()

    def test_user_profile_roundtrip(self) -> None:
        """Persist and fetch user profiles using the database."""
        user_id = f'user_{uuid.uuid4().hex}'
        response = self.client.post(
            '/user/upsert',
            json={
                'user_id': user_id,
                'email': 'user@example.com',
                'plan_tier': 'starter',
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json().get('plan_tier'), 'starter')

        response = self.client.get('/user', params={'user_id': user_id})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json().get('plan_tier'), 'starter')

        response = self.client.post(
            '/user/plan',
            json={'user_id': user_id, 'plan_tier': 'growth'},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json().get('plan_tier'), 'growth')

    def test_selection_roundtrip(self) -> None:
        """Persist and fetch channel selections using the database."""
        user_id = f'user_{uuid.uuid4().hex}'
        payload = {
            'user_id': user_id,
            'channels': [
                {
                    'id': 'channel-a',
                    'title': 'Channel A',
                    'thumbnail_url': 'https://example.com/a.jpg',
                },
                {
                    'id': 'channel-b',
                    'title': 'Channel B',
                    'thumbnail_url': 'https://example.com/b.jpg',
                },
            ],
            'selected_ids': ['channel-a', 'channel-b', 'channel-c'],
        }
        response = self.client.post('/selection', json=payload)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            set(response.json().get('selected_ids', [])),
            {'channel-a', 'channel-b'},
        )

        response = self.client.get('/selection', params={'user_id': user_id})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            set(response.json().get('selected_ids', [])),
            {'channel-a', 'channel-b'},
        )

    def test_archive_roundtrip(self) -> None:
        """Persist and remove archive entries using the database."""
        user_id = f'user_{uuid.uuid4().hex}'
        video_id = f'video_{uuid.uuid4().hex}'

        response = self.client.post(
            '/archives/toggle',
            json={'user_id': user_id, 'video_id': video_id},
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json().get('archived'))

        response = self.client.get('/archives', params={'user_id': user_id})
        self.assertEqual(response.status_code, 200)
        items = response.json().get('items', [])
        self.assertTrue(
            any(item.get('video_id') == video_id for item in items)
        )

        response = self.client.post(
            '/archives/toggle',
            json={'user_id': user_id, 'video_id': video_id},
        )
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json().get('archived'))

        response = self.client.post(
            '/archives/clear', json={'user_id': user_id}
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json().get('cleared'))

        response = self.client.get('/archives', params={'user_id': user_id})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json().get('items', []), [])

    def test_user_state_roundtrip(self) -> None:
        """Persist and fetch per-user app state using the database."""
        user_id = f'user_{uuid.uuid4().hex}'
        payload = {
            'user_id': user_id,
            'selection_change_day': 20260206,
            'selection_changes_today': 1,
            'opened_video_ids': ['abc12345xyz', 'abc12345xyz', 'def67890uvw'],
        }
        response = self.client.post('/user/state', json=payload)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body.get('selection_change_day'), 20260206)
        self.assertEqual(body.get('selection_changes_today'), 1)
        self.assertEqual(
            body.get('opened_video_ids'),
            ['abc12345xyz', 'def67890uvw'],
        )
        response = self.client.get('/user/state', params={'user_id': user_id})
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body.get('selection_change_day'), 20260206)
        self.assertEqual(body.get('selection_changes_today'), 1)
        self.assertEqual(
            body.get('opened_video_ids'),
            ['abc12345xyz', 'def67890uvw'],
        )

    def test_selection_concurrent_writes_remain_consistent(self) -> None:
        """Concurrent selection writes should not leave duplicate links."""
        import server.app as app_module
        from server.db import get_session
        from server.models import UserChannel

        user_id = f'user_{uuid.uuid4().hex}'
        channels = [
            {
                'id': 'channel-a',
                'title': 'Channel A',
                'thumbnail_url': 'https://example.com/a.jpg',
            },
            {
                'id': 'channel-b',
                'title': 'Channel B',
                'thumbnail_url': 'https://example.com/b.jpg',
            },
            {
                'id': 'channel-c',
                'title': 'Channel C',
                'thumbnail_url': 'https://example.com/c.jpg',
            },
        ]
        payload_a = {
            'user_id': user_id,
            'channels': channels,
            'selected_ids': ['channel-a'],
        }
        payload_b = {
            'user_id': user_id,
            'channels': channels,
            'selected_ids': ['channel-b', 'channel-c'],
        }
        expected_sets = {
            frozenset(payload_a['selected_ids']),
            frozenset(payload_b['selected_ids']),
        }
        barrier = threading.Barrier(3)

        def _write_selection(payload):
            with TestClient(app_module.app) as client:
                barrier.wait(timeout=5)
                return client.post('/selection', json=payload)

        with ThreadPoolExecutor(max_workers=2) as executor:
            future_a = executor.submit(_write_selection, payload_a)
            future_b = executor.submit(_write_selection, payload_b)
            barrier.wait(timeout=5)
            response_a = future_a.result(timeout=10)
            response_b = future_b.result(timeout=10)

        self.assertEqual(response_a.status_code, 200)
        self.assertEqual(response_b.status_code, 200)

        response = self.client.get('/selection', params={'user_id': user_id})
        self.assertEqual(response.status_code, 200)
        final_selected = set(response.json().get('selected_ids', []))
        self.assertIn(frozenset(final_selected), expected_sets)

        with get_session() as session:
            self.assertIsNotNone(session)
            rows = (
                session.query(UserChannel)
                .filter(
                    UserChannel.user_id == user_id,
                    UserChannel.is_selected.is_(True),
                )
                .all()
            )
            row_ids = [row.channel_id for row in rows]
        self.assertEqual(len(row_ids), len(set(row_ids)))
        self.assertEqual(set(row_ids), final_selected)


if __name__ == '__main__':
    unittest.main()
