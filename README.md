# TubeTidy

TubeTidy is an iOS-first Flutter app with web support for people who want to keep up with YouTube subscriptions without watching every upload. It signs in with Google, syncs subscriptions, lets users choose the channels they care about, and generates short 3-line summaries on demand.

The project pairs a Flutter client with a FastAPI transcript service. The backend uses a caption-first pipeline, falls back to `yt-dlp` plus OpenAI Whisper speech-to-text when needed, and returns compact summaries designed for quick scanning.

## Why It Exists

YouTube subscriptions are easy to accumulate and hard to keep current. TubeTidy is built around a simple idea:

- sync the channels a user already follows
- reduce the feed to a manageable set of selected channels
- summarize long videos into something readable in seconds
- keep the useful ones in a lightweight archive calendar

## Product Snapshot

### User flow
1. Sign in with Google
2. Import YouTube subscriptions
3. Select channels within the current plan limit
4. Request a summary for any recent upload
5. Save useful summaries and review them later by date

### Core features
- Google sign-in and YouTube subscription sync
- Channel selection policy with plan-based limits and daily swap cooldown
- On-demand 3-line summaries
- Caption-first transcript retrieval
- `yt-dlp` audio extraction plus STT fallback when captions are missing
- Saved summary archive with calendar view
- Local transcript and summary caching
- iOS-first glass UI with web support
- Multilingual UI strings for English, Korean, Japanese, Chinese, and Spanish

## Tech Stack

| Layer | Stack |
| --- | --- |
| App | Flutter, Riverpod, GoRouter |
| Backend | FastAPI, SQLAlchemy |
| Video pipeline | YouTube Data API, `yt-dlp`, caption parsing, OpenAI Whisper fallback |
| AI summary | OpenAI API |
| Persistence | Local cache by default, optional PostgreSQL for backend persistence |
| Tooling | Docker Compose, shell scripts, unit tests, integration tests |

## Architecture

### Client
- onboarding and Google authentication
- YouTube sync and channel selection
- summary feed and queue state
- saved summary calendar
- subscription plan screen and purchase hooks
- settings, local cache cleanup, and app metadata

### Backend
- transcript retrieval and normalization
- queue and rate-limit protections
- OpenAI summary generation
- Google ID token verification for protected routes
- optional PostgreSQL-backed persistence for users, selections, and archives

## Repository Layout

```text
lib/            Flutter application code
server/         FastAPI transcript and summary service
test/           Flutter widget and app tests
integration_test/ Flutter integration test entrypoints
docs/           architecture, operations, security, and refactor notes
scripts/        local run, migration, quality, and deployment helpers
```

## Local Development

### Requirements
- Flutter 3.19+
- Python 3.9+
- Google OAuth credentials for web and iOS
- OpenAI API key
- PostgreSQL 14+ only if you want backend persistence enabled

### 1. Install Flutter dependencies

```bash
flutter pub get
```

### 2. Create `.env`

Create a root-level `.env` file:

```env
TRANSCRIPT_API_URL=http://127.0.0.1:5055
OPENAI_API_KEY=YOUR_OPENAI_API_KEY
OPENAI_SUMMARY_MODEL=gpt-4.1-nano
DATABASE_URL=postgresql+psycopg2://youtube_summary:youtube_summary@127.0.0.1:5433/youtube_summary
BACKEND_REQUIRE_AUTH=true
GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
APP_VERSION=1.0.0
BUILD_NUMBER=1
PRIVACY_POLICY_URL=https://example.com/privacy
TERMS_URL=https://example.com/terms
SUPPORT_EMAIL=support@example.com
SUPPORT_URL=https://example.com/support
```

Optional overrides:

```env
CORS_ALLOWED_ORIGINS=https://your-web-domain.com,https://admin.your-domain.com
YTDLP_COOKIES_PATH=/path/to/cookies.txt
YTDLP_COOKIES_FROM_BROWSER=chrome
```

### 3. Start PostgreSQL if needed

```bash
docker compose up -d postgres
```

Local mapping is `127.0.0.1:5433 -> container:5432`.

If you are using the database manually:

```bash
python3 scripts/migrate_db.py
```

`./scripts/run_transcript_server.sh` also runs migrations automatically when `DATABASE_URL` is set.

### 4. Start the transcript server

```bash
./scripts/run_transcript_server.sh
```

### 5. Run the Flutter app

#### Web

```bash
flutter run -d web-server \
  --web-port 5301 \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com \
  --dart-define=TRANSCRIPT_API_URL=http://127.0.0.1:5055
```

#### iOS

Set these values in `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig`:

```text
GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID=com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID
```

Then run:

```bash
flutter run -d ios
```

## Backend Auth

When `BACKEND_REQUIRE_AUTH=true`, protected routes require a Google bearer token and the server verifies ID tokens against the configured client IDs.

Keep this enabled in release:

- `BACKEND_REQUIRE_AUTH=true`
- `GOOGLE_WEB_CLIENT_ID` and/or `GOOGLE_IOS_CLIENT_ID` configured on the server

For local debugging only, you can temporarily disable it:

```env
BACKEND_REQUIRE_AUTH=false
```

## Google OAuth and YouTube Setup

1. Create web and iOS OAuth client IDs in Google Cloud Console
2. Enable YouTube Data API v3
3. Add local web origins such as `http://127.0.0.1:5301` and `http://localhost:5301`

## Testing

### Flutter

```bash
flutter test
```

### Quality checks

```bash
./scripts/check_quality.sh
```

### Backend

```bash
./.venv/bin/python -m unittest server.tests.test_app
```

### Backend with PostgreSQL integration

```bash
DATABASE_URL=postgresql+psycopg2://youtube_summary:youtube_summary@127.0.0.1:5433/youtube_summary python3 scripts/migrate_db.py
DATABASE_URL=postgresql+psycopg2://youtube_summary:youtube_summary@127.0.0.1:5433/youtube_summary ./.venv/bin/python -m unittest server.tests.test_db_integration
```

If PostgreSQL is unavailable, the DB integration test is skipped automatically.

## Build for Web

```bash
flutter build web \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com \
  --dart-define=TRANSCRIPT_API_URL=http://127.0.0.1:5055
python3 -m http.server 5301 --bind 127.0.0.1 --directory build/web
```

## Documentation

- [`docs/README.md`](docs/README.md): documentation index
- [`docs/architecture/`](docs/architecture/): app structure and styling decisions
- [`docs/operations/`](docs/operations/): deployment and operational notes
- [`docs/security/`](docs/security/): security hardening checklist
- [`docs/reports/`](docs/reports/): refactor and implementation notes

## Credits

Idea and AI concept by **Yunjoo Cho**
Contact: [rachelcyj99@gmail.com](mailto:rachelcyj99@gmail.com)
