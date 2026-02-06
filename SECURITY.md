# Security Baseline

## Backend Auth
- Set `BACKEND_REQUIRE_AUTH=true` in production.
- Configure at least one valid audience:
  - `GOOGLE_WEB_CLIENT_ID`
  - `GOOGLE_IOS_CLIENT_ID`
  - or `GOOGLE_CLIENT_IDS` (comma-separated)
- Protected APIs require `Authorization: Bearer <Google token>`:
  - `/user`
  - `/selection`
  - `/archives`

## Network Controls
- Restrict CORS origins with `CORS_ALLOWED_ORIGINS`.
- Keep credentials disabled for wildcard origins.
- Serve backend behind HTTPS reverse proxy (Nginx/ALB/Cloudflare).
- Keep port `5055` private to trusted network paths.

## Data & Abuse Controls
- Transcript API has per-client in-memory rate limiting:
  - `TRANSCRIPT_RATE_LIMIT_PER_WINDOW`
  - `TRANSCRIPT_RATE_LIMIT_WINDOW_SECONDS`
- Selection payload limits:
  - `MAX_SELECTION_CHANNELS`
- Runtime DB migrations enforce duplicate protection:
  - unique user/channel pairs
  - unique user/archive video pairs

## Secret Handling
- Never commit real API keys.
- Store `OPENAI_API_KEY` and DB credentials in secret manager (AWS/GCP/Vault).
- Rotate secrets periodically and immediately after suspected exposure.

## Release Checklist
1. `BACKEND_REQUIRE_AUTH=true`
2. Google client IDs set on server and app build config
3. `CORS_ALLOWED_ORIGINS` matches only production domains
4. DB reachable only from backend security group
5. Automated tests pass:
   - `flutter test`
   - `./.venv/bin/python -m unittest server.tests.test_app`
   - DB integration tests with production-like DB settings
