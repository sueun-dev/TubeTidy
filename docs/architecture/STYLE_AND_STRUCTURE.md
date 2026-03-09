# Style And Structure

This repository follows official style guidance rather than an arbitrary
"perfect" layout.

## Source Standards
- Dart and Flutter style: Effective Dart and Flutter's official
  architecture guidance.
- Python style: Google's Python Style Guide, enforced pragmatically
  with `pylint` and a small backend package layout.

Official references:
- https://dart.dev/effective-dart/style
- https://docs.flutter.dev/app-architecture/guide
- https://google.github.io/styleguide/pyguide.html

## Repository Layout
- `lib/models`: immutable domain models used across the client.
- `lib/services`: IO, persistence, backend, and platform integration.
- `lib/state`: application state, policies, and controllers.
- `lib/screens`: top-level presentation surfaces.
- `lib/widgets`: reusable presentation building blocks.
- `server/config.py`: backend configuration and immutable constants.
- `server/schemas.py`: FastAPI request payload models.
- `server/app.py`: route wiring and orchestration.
- `server/db.py`, `server/models.py`: persistence layer.
- `scripts/check_quality.sh`: single-entry quality gate.

## Why This Layout
- The Flutter client is still small enough that a strict feature-first
  re-layout would create more churn than clarity.
- The backend had the largest structural hotspot, so configuration and
  API schemas were extracted first to reduce the `server/app.py`
  monolith without changing behavior.
- Quality checks are centralized so format, lint, tests, and optional
  database integration use one command.

## Quality Gate
Run:

```bash
./scripts/check_quality.sh
```

The script runs:
- `dart format --set-exit-if-changed`
- `flutter analyze`
- `flutter test`
- `pylint`
- `python -m unittest discover -s server/tests`
- DB migration and integration tests when `DATABASE_URL` or
  `DATABASE_URL_UNPOOLED` is configured
