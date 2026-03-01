## Thank You
아이디어 및 A.I 아이디어 제공: **Yunjoo Cho**  
Contact: [rachelcyj99@gmail.com](mailto:rachelcyj99@gmail.com)

# TubeTidy

AI-powered YouTube summary app (Flutter) that syncs subscriptions, extracts captions/audio, and generates concise 3-line summaries on demand.

## Highlights
- Google OAuth + YouTube subscription sync
- Channel selection with limits based on subscription count (and daily change cooldown)
- On-demand summarization: captions -> yt-dlp -> audio + Whisper fallback
- 3-line summaries via OpenAI
- Per-user local caching to reduce repeat costs
- iOS-first UI with web support

## Architecture
- **Flutter client** (iOS / Web)
- **Transcript server** (FastAPI on port `5055`)
  - Caption fetch (timedtext + yt-dlp)
  - Audio download + Whisper STT fallback
  - Summary generation via OpenAI

## Documentation
- `docs/README.md`: documentation index
- `docs/operations/`: runbooks, release checklist, infra status
- `docs/reports/`: refactoring/change reports
- `docs/security/`: security checklist and release hardening notes
- `docs/notes/`: working notes and troubleshooting logs
- `docs/confirm/`: centralized per-folder validation snapshots

## Requirements
- Flutter 3.19+
- Python 3.9+
- Google OAuth credentials (iOS + Web)
- OpenAI API key (for Whisper + summaries)
- PostgreSQL 14+ (optional, enables server-side persistence)
- Google ID token verification settings (required for production backend auth)

## Setup
### 1) Install dependencies
```bash
flutter pub get
```

### 2) Create `.env`
Create `.env` at repo root:
```
TRANSCRIPT_API_URL=http://127.0.0.1:5055
OPENAI_API_KEY=YOUR_OPENAI_API_KEY
OPENAI_SUMMARY_MODEL=gpt-4.1-nano
DATABASE_URL=postgresql+psycopg2://youtube_summary:youtube_summary@127.0.0.1:5433/youtube_summary
# Backend security (recommended for release)
BACKEND_REQUIRE_AUTH=true
GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
# Optional: override allowed origins
# CORS_ALLOWED_ORIGINS=https://your-web-domain.com,https://admin.your-domain.com
# Optional app metadata
APP_VERSION=1.0.0
BUILD_NUMBER=1
PRIVACY_POLICY_URL=https://example.com/privacy
TERMS_URL=https://example.com/terms
SUPPORT_EMAIL=support@example.com
SUPPORT_URL=https://example.com/support
```

### 2.1) (Optional) Start PostgreSQL locally
```bash
docker compose up -d postgres
```
Default local mapping is `127.0.0.1:5433 -> container:5432`.
The server auto-creates tables and runtime indexes when `DATABASE_URL` is set.

### 3) Run transcript server
```bash
./scripts/run_transcript_server.sh
```

### 4) Run the app
**Web (local testing)**
```bash
flutter run -d web-server \
  --web-port 5301 \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com \
  --dart-define=TRANSCRIPT_API_URL=http://127.0.0.1:5055
```

**iOS**
Update `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig`:
```
GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID=com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID
```
Then:
```bash
flutter run -d ios
```

## Backend Auth (Release)
- Protected endpoints (`/user`, `/selection`, `/archives`) require Google `Bearer` token when `BACKEND_REQUIRE_AUTH=true`.
- Flutter app now forwards Google `idToken` automatically after sign-in.
- For release, keep:
  - `BACKEND_REQUIRE_AUTH=true`
  - `GOOGLE_WEB_CLIENT_ID` and/or `GOOGLE_IOS_CLIENT_ID` configured on server.
- For local troubleshooting only, you can temporarily disable auth:
  - `BACKEND_REQUIRE_AUTH=false`

## Google OAuth / YouTube API setup
1. Create OAuth client IDs (iOS + Web) in Google Cloud Console
2. Enable **YouTube Data API v3**
3. Add authorized JavaScript origins for web:
   - `http://127.0.0.1:5301`
   - `http://localhost:5301`

## Optional: Web auto sign-in
Web auto sign-in is **enabled by default**.
Disable it only when debugging FedCM/CORS/popup issues:
```bash
--dart-define=WEB_AUTO_SIGNIN=false
```

## Optional: Cookies for restricted videos
Some videos are restricted (age/region/login). You can pass cookies to yt-dlp:
```
YTDLP_COOKIES_PATH=/path/to/cookies.txt
# or
YTDLP_COOKIES_FROM_BROWSER=chrome
```

## Build (web)
```bash
flutter build web \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com \
  --dart-define=TRANSCRIPT_API_URL=http://127.0.0.1:5055
python3 -m http.server 5301 --bind 127.0.0.1 --directory build/web
```

## Testing
```bash
flutter test
./.venv/bin/python -m unittest server.tests.test_app
DATABASE_URL=postgresql+psycopg2://youtube_summary:youtube_summary@127.0.0.1:5433/youtube_summary ./.venv/bin/python -m unittest server.tests.test_db_integration
```
If PostgreSQL is unavailable, `server.tests.test_db_integration` is skipped automatically.

---
If you want a simple demo flow:
1) Run transcript server
2) Run web app
3) Login with Google
4) Select channels (limit depends on subscription count)
5) Tap **"요약하기"** next to a video
