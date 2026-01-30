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

## Requirements
- Flutter 3.19+
- Python 3.9+
- Google OAuth credentials (iOS + Web)
- OpenAI API key (for Whisper + summaries)

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
```

### 3) Run transcript server
```bash
./scripts/run_transcript_server.sh
```

### 4) Run the app
**Web (local testing)**
```bash
flutter run -d web-server \
  --web-port 5201 \
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

## Google OAuth / YouTube API setup
1. Create OAuth client IDs (iOS + Web) in Google Cloud Console
2. Enable **YouTube Data API v3**
3. Add authorized JavaScript origins for web:
   - `http://127.0.0.1:5201`
   - `http://localhost:5201`

## Optional: Web auto sign-in
Web auto sign-in is **disabled by default** to avoid FedCM/CORS issues.
Enable with:
```bash
--dart-define=WEB_AUTO_SIGNIN=true
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
python3 -m http.server 5201 --bind 127.0.0.1 --directory build/web
```

## Testing
```bash
flutter test
```

---
If you want a simple demo flow:
1) Run transcript server
2) Run web app
3) Login with Google
4) Select channels (limit depends on subscription count)
5) Tap **"요약하기"** next to a video
