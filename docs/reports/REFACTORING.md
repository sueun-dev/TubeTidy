# Refactoring Report

## Scope
- Backend: `server/app.py`, `server/tests/test_app.py`, `server/tests/test_db_integration.py`
- Frontend data path: `lib/services/*.dart`, `lib/state/app_controller.dart`
- iOS Liquid Glass UI consistency: `lib/screens/*.dart`, `lib/widgets/*.dart`, `pubspec.yaml`

## Backend Improvements
- Added transcript request guardrails:
  - `video_id` format validation
  - `max_chars` normalization (`_sanitize_max_chars`)
- Added backend security hardening:
  - optional/required Google token auth gate (`BACKEND_REQUIRE_AUTH`)
  - protected endpoint authorization for `/user`, `/selection`, `/archives`
  - token audience validation against configured Google client IDs
  - response security headers (`X-Content-Type-Options`, `X-Frame-Options`, etc.)
  - transcript endpoint rate limiting per client
- Reduced data waste and DB overhead on selection save:
  - deduplicated/normalized payload
  - bulk channel fetch to avoid N+1 query pattern
  - deterministic/sorted response payload
  - payload size caps (`MAX_SELECTION_CHANNELS`)
- Improved resilience:
  - network exception handling for caption endpoints
  - safe JSON parsing for OpenAI responses
  - safer cache file access (invalid id short-circuit)
- Fixed archive persistence correctness:
  - resolved DB foreign-key failure during archive toggle
  - ensured placeholder rows for archive-only videos
- Optimized temp audio handling:
  - replaced full read/write copy path with `shutil.copyfile` to a unique temp file
- DB runtime migration added:
  - duplicate cleanup and unique/index creation for `user_channels` and `archives`
- Server startup script efficiency:
  - `.env` is loaded automatically
  - virtualenv creation/install now runs only when needed (requirements hash based)

## Frontend Improvements
- Network/service robustness:
  - timeout handling on transcript/selection/archive/user APIs
  - filtered selection payload to send only selected channels
- Backend auth propagation:
  - added `lib/services/backend_api.dart` to centralize base URL + auth headers
  - Google sign-in token is propagated to backend requests automatically
- YouTube API efficiency:
  - channel ID deduplication
  - batched parallel fetch for latest videos
  - dedupe videos by video id
  - structured `YouTubeApiException` for auth retry logic
- App state queue performance:
  - changed transcript queue from `List` with `removeAt(0)` to `Queue` with `removeFirst()`
- Render efficiency:
  - reduced repeated list scans by introducing local channel map lookups in screens
- Naming and structure refactor:
  - `lib/config.dart` -> `lib/app_config.dart`
  - `lib/state/app_state.dart` -> `lib/state/app_controller.dart`
  - `lib/state/ui_state.dart` -> `lib/state/ui_providers.dart`
  - removed unused model files: `payment.dart`, `summary.dart`, `youtube_account.dart`
- Dependency cleanup:
  - removed local path override for `google_sign_in_web`
  - deleted vendored `packages/google_sign_in_web` folder (now using pub package directly)
- Local DB cleanup:
  - dropped unused legacy tables: `payments`, `summaries`, `youtube_accounts`

## iOS Liquid Glass Consistency
- Updated plan/connect screens and plan cards to use shared Liquid Glass surfaces, spacing, colors, and typography.
- Applied small consistency fixes (const widgets, deprecated color API migration to `withValues` where touched).

## Validation Results
- Backend unit tests:
  - `./.venv/bin/python -m unittest server.tests.test_app` -> PASS
- Backend DB integration tests:
  - `DATABASE_URL=postgresql+psycopg2://youtube_summary:youtube_summary@127.0.0.1:5433/youtube_summary ./.venv/bin/python -m unittest server.tests.test_db_integration` -> PASS
- Backend full test discovery:
  - `./.venv/bin/python -m unittest discover -s server/tests` -> PASS
- Flutter tests:
  - `flutter test` -> PASS
- Flutter analysis (full project):
  - `flutter analyze` -> PASS (no issues)

## Operational Notes
- A Python command failure was documented in `docs/notes/MUSTREAD.md` per project rule.
- Added `docs/security/SECURITY.md` release checklist for auth/CORS/secret handling.
- No Codex server operations were performed.
