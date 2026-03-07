"""High-volume matrix tests for backend logic helpers."""

import os
from itertools import product
import unittest

from fastapi import HTTPException

os.environ.setdefault('BACKEND_REQUIRE_AUTH', 'false')

import server.app as backend


_SANITIZE_MAX_CHARS_CASES = [None] + list(range(-600, 10601, 25))
_PLAN_LIMIT_CASES = list(
    product(
        [None, '', 'free', 'starter', 'growth', 'unlimited', 'lifetime', 'bogus'],
        range(0, 61),
    )
)
_SUMMARY_PREFIXES = ['• ', '- ', '1. ', '  9. ']
_SUMMARY_LINES = ['첫 줄', '둘째 줄', '셋째 줄', '넷째 줄', '다섯째 줄']
_SUMMARY_CASES = [
    (prefix, available_lines, requested_lines)
    for prefix in _SUMMARY_PREFIXES
    for available_lines in range(1, len(_SUMMARY_LINES) + 1)
    for requested_lines in range(1, available_lines + 1)
]
_OPENED_VIDEO_CANDIDATES = [
    'video_000',
    ' bad ',
    'video_001',
    'video_000',
    '../bad',
    'video_002',
]
_OPENED_VIDEO_CASES = [
    [
        candidate
        for index, candidate in enumerate(_OPENED_VIDEO_CANDIDATES)
        if mask & (1 << index)
    ]
    for mask in range(1 << len(_OPENED_VIDEO_CANDIDATES))
]
_CACHE_KEY_CASES = list(
    product(
        ['video_alpha01', 'video_beta_02'],
        [300, 1200, 10000],
        [False, True],
        [None, 1, 3, 5],
    )
)
_PARSER_CASES = [
    ('WEBVTT\n\n00:00.000 --> 00:01.000\nhello', 'vtt', 'hello'),
    ('{"events":[{"segs":[{"utf8":"hello"},{"utf8":" world"}]}]}', 'json3', 'hello world'),
    ('<transcript><text>hello</text><text>world</text></transcript>', 'xml', 'hello world'),
    ('<tt><body><p>hello</p><p>world</p></body></tt>', 'ttml', 'hello world'),
]
_TOTAL_LOGIC_CASES = (
    len(_SANITIZE_MAX_CHARS_CASES)
    + len(_PLAN_LIMIT_CASES)
    + len(_SUMMARY_CASES)
    + len(_OPENED_VIDEO_CASES)
    + len(_CACHE_KEY_CASES)
    + len(_PARSER_CASES)
)


class LogicMatrixTest(unittest.TestCase):
    """Validate backend helper invariants across a large case matrix."""

    def test_logic_case_count_exceeds_500(self) -> None:
        """Keep the matrix size explicitly above the requested threshold."""
        self.assertGreaterEqual(_TOTAL_LOGIC_CASES, 500)

    def test_sanitize_max_chars_matrix(self) -> None:
        """_sanitize_max_chars should clamp inputs consistently."""
        for raw in _SANITIZE_MAX_CHARS_CASES:
            with self.subTest(raw=raw):
                expected = (
                    backend.TRANSCRIPT_DEFAULT_MAX_CHARS
                    if raw is None
                    else max(
                        backend.TRANSCRIPT_MIN_MAX_CHARS,
                        min(backend.TRANSCRIPT_MAX_MAX_CHARS, int(raw)),
                    )
                )
                self.assertEqual(backend._sanitize_max_chars(raw), expected)

    def test_selection_plan_limit_matrix(self) -> None:
        """Selection limits should accept only counts allowed by the tier."""
        expected_limits = {
            None: 3,
            '': 3,
            'free': 3,
            'starter': 10,
            'growth': 50,
            'unlimited': None,
            'lifetime': None,
            'bogus': 3,
        }
        for plan_tier, count in _PLAN_LIMIT_CASES:
            with self.subTest(plan_tier=plan_tier, count=count):
                ids = [f'video_{index:03d}' for index in range(count)]
                expected_limit = expected_limits[plan_tier]
                self.assertEqual(
                    backend._channel_limit_for_plan_tier(plan_tier),
                    expected_limit,
                )
                if expected_limit is None or count <= expected_limit:
                    backend._enforce_selection_plan_limit(plan_tier, ids)
                    continue
                with self.assertRaises(HTTPException) as exc_context:
                    backend._enforce_selection_plan_limit(plan_tier, ids)
                self.assertEqual(exc_context.exception.status_code, 403)
                self.assertEqual(
                    exc_context.exception.detail,
                    'selected channel limit exceeded for current plan',
                )

    def test_normalize_summary_matrix(self) -> None:
        """normalize_summary should strip prefixes and keep requested lines."""
        for prefix, available_lines, requested_lines in _SUMMARY_CASES:
            with self.subTest(
                prefix=prefix,
                available_lines=available_lines,
                requested_lines=requested_lines,
            ):
                source = '\n'.join(
                    f'{prefix}{_SUMMARY_LINES[index]}'
                    for index in range(available_lines)
                )
                normalized = backend.normalize_summary(source, requested_lines)
                self.assertEqual(
                    normalized.splitlines(),
                    _SUMMARY_LINES[:requested_lines],
                )

    def test_normalize_opened_video_ids_matrix(self) -> None:
        """Opened-video normalization should drop invalid IDs and de-dupe."""
        for raw_ids in _OPENED_VIDEO_CASES:
            with self.subTest(raw_ids=raw_ids):
                expected = []
                seen = set()
                for raw in raw_ids:
                    candidate = raw.strip()
                    if not backend.VIDEO_ID_PATTERN.fullmatch(candidate):
                        continue
                    if candidate in seen:
                        continue
                    seen.add(candidate)
                    expected.append(candidate)
                self.assertEqual(
                    backend._normalize_opened_video_ids(raw_ids),
                    expected,
                )

    def test_normalize_opened_video_ids_enforces_cap(self) -> None:
        """Opened-video normalization should stop at MAX_OPENED_VIDEO_IDS."""
        raw_ids = [f'video_{index:03d}' for index in range(backend.MAX_OPENED_VIDEO_IDS + 25)]
        normalized = backend._normalize_opened_video_ids(raw_ids)
        self.assertEqual(len(normalized), backend.MAX_OPENED_VIDEO_IDS)
        self.assertEqual(normalized[0], 'video_000')
        self.assertEqual(
            normalized[-1],
            f'video_{backend.MAX_OPENED_VIDEO_IDS - 1:03d}',
        )

    def test_transcript_cache_key_matrix(self) -> None:
        """Transcript cache keys should be stable for normalized request shapes."""
        seen_by_signature = {}
        for video_id, max_chars, summarize, summary_lines in _CACHE_KEY_CASES:
            with self.subTest(
                video_id=video_id,
                max_chars=max_chars,
                summarize=summarize,
                summary_lines=summary_lines,
            ):
                key = backend._build_transcript_cache_key(
                    video_id=video_id,
                    max_chars=max_chars,
                    summarize=summarize,
                    summary_lines=summary_lines,
                )
                normalized_signature = (
                    video_id,
                    max_chars,
                    summarize,
                    max(1, min(5, summary_lines or 3)),
                )
                self.assertEqual(len(key), 32)
                existing = seen_by_signature.get(normalized_signature)
                if existing is None:
                    seen_by_signature[normalized_signature] = key
                else:
                    self.assertEqual(key, existing)

        self.assertEqual(
            len(set(seen_by_signature.values())),
            len(seen_by_signature),
        )

    def test_caption_payload_parser_matrix(self) -> None:
        """Caption payload dispatch should select the correct parser."""
        for raw, ext, expected in _PARSER_CASES:
            with self.subTest(ext=ext):
                self.assertEqual(backend.parse_caption_payload(raw, ext), expected)


if __name__ == '__main__':
    unittest.main()
