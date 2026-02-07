# MUSTREAD

## 2026-02-06 Python 테스트 실행 오류 기록

### 발생한 오류
- 명령어: `python3 -m unittest server.tests.test_app`
- 오류: `ModuleNotFoundError: No module named 'fastapi'`

### 왜 발생했는가
- 시스템 Python(`python3`) 환경에 프로젝트 의존성(`fastapi` 등)이 설치되어 있지 않았다.
- 이 저장소는 `.venv` 가상환경 기준으로 의존성을 관리하고 있다.

### 다시는 같은 실수를 하지 않기 위한 규칙
- Python 관련 실행은 항상 가상환경 우선:
  - `./.venv/bin/python ...`
- 테스트 전 의존성 검증:
  - `./.venv/bin/python -m pip show fastapi`
- 필요 시 의존성 설치:
  - `./.venv/bin/python -m pip install -r server/requirements.txt`

### 표준 실행 절차
1. `./.venv/bin/python -m pip show fastapi` 로 의존성 확인
2. 없으면 `./.venv/bin/python -m pip install -r server/requirements.txt`
3. 테스트 실행: `./.venv/bin/python -m unittest server.tests.test_app`

---

## 2026-02-06 DB 통합 테스트 환경변수 오류 기록

### 발생한 오류
- 명령어: `./.venv/bin/python -m unittest server.tests.test_db_integration`
- 오류: `RuntimeError: DATABASE_URL must be set for DB integration tests.`

### 왜 발생했는가
- DB 통합 테스트는 `setUpClass()`에서 `os.getenv('DATABASE_URL')`를 직접 확인한다.
- `.env`는 테스트 시작 전에 자동 export되지 않기 때문에, 셸 환경변수에 `DATABASE_URL`이 없으면 즉시 실패한다.

### 다시는 같은 실수를 하지 않기 위한 규칙
- DB 통합 테스트 실행 시 `DATABASE_URL`을 명시적으로 주입한다.
- 로컬 고정값을 사용할 때는 프로젝트 표준 포트(`5433`)를 사용한다.

### 표준 실행 절차
1. Postgres 상태 확인: `docker compose ps postgres`
2. 통합 테스트 실행:
   - `DATABASE_URL=postgresql+psycopg2://youtube_summary:youtube_summary@127.0.0.1:5433/youtube_summary ./.venv/bin/python -m unittest server.tests.test_db_integration`

---

## 2026-02-06 모델 리로드 디버깅 오류 기록

### 발생한 오류
- 명령어: Python REPL 스크립트에서 `importlib.reload(server.models)` 수행
- 오류: `sqlalchemy.exc.InvalidRequestError: Table 'users' is already defined for this MetaData instance`

### 왜 발생했는가
- SQLAlchemy Declarative 모델을 같은 프로세스에서 재정의(reload)하면 메타데이터에 동일 테이블이 중복 등록된다.

### 다시는 같은 실수를 하지 않기 위한 규칙
- 모델 디버깅 시 `server.models`를 강제 reload하지 않는다.
- 검증이 필요하면 새 Python 프로세스를 실행해서 import한다.

---

## 2026-02-06 OAuth origin_mismatch 재발 방지 규칙

### 발생한 오류
- 오류: `Error 400: origin_mismatch` (Google OAuth 로그인 차단)

### 왜 발생했는가
- 잘못된 GCP 프로젝트에서 OAuth JavaScript origin을 수정하려고 하거나,
- 실제 실행 포트와 OAuth 클라이언트 등록 origin이 일치하지 않았다.

### 다시는 같은 실수를 하지 않기 위한 고정 규칙
- OAuth/YouTube 설정은 반드시 아래 프로젝트에서만 작업:
  - 프로젝트 ID: `plated-valor-485818-a0`
  - 프로젝트 이름: `youtube-summary`
  - Web Client ID: `594746397559-lo8fattdnn2pii8ub8nrdkh43rrahrhb.apps.googleusercontent.com`
- 로컬 테스트 서버는 아래 포트만 사용:
  - 백엔드: `http://127.0.0.1:5055`
  - 웹: `http://localhost:5301`
- OAuth Authorized JavaScript origins에는 아래를 항상 포함:
  - `http://localhost:5301`
  - `http://127.0.0.1:5301`

### 표준 실행 절차
1. `gcloud config set project plated-valor-485818-a0`
2. `tmux` 세션 확인: `tmux ls | rg 'tubetidy-api-5055|tubetidy-web-5301'`
3. OAuth 콘솔에서 위 Web Client ID의 origin 등록값 확인 후 저장

---

## 2026-02-06 npm e2e 도구 실행 오류 기록

### 발생한 오류
- 명령어: `npx -y -p playwright node -e "require('playwright')..."`
- 오류: `Error: Cannot find module 'playwright'`

### 왜 발생했는가
- 현재 환경에서 `npx -p` 방식으로 설치된 패키지가 즉시 `require` 경로로 연결되지 않았다.

### 다시는 같은 실수를 하지 않기 위한 규칙
- Playwright 실행은 임시 작업 디렉토리에서 명시적 설치 후 실행한다.

### 표준 실행 절차
1. `TMP_DIR=$(mktemp -d); cd "$TMP_DIR"`
2. `npm init -y`
3. `npm i playwright --silent`
4. `node` 스크립트로 e2e 스모크 실행

---

## 2026-02-06 웹 흰 화면(White Screen) 오류 기록

### 발생한 오류
- 증상: `localhost:5301` 접속 시 흰 화면만 표시되고 앱 본문이 렌더되지 않음
- 콘솔: `DDC is about to load ...` 이후 앱 메인 진입 로그가 멈춤

### 왜 발생했는가
- `web/flutter_bootstrap.js`에서 `canvasKitBaseUrl: "/canvaskit/"`를 강제했는데,
  현재 로컬 디버그 서버에서 해당 경로가 보장되지 않아 CanvasKit 로딩 실패가 발생할 수 있었다.
- 추가로 `flutter run -d web-server` 디버그 모드는 브라우저/확장 상태에 따라 메인 진입이 불안정할 수 있다.

### 다시는 같은 실수를 하지 않기 위한 규칙
- `web/flutter_bootstrap.js`에서 로컬 CanvasKit 경로를 강제하지 않는다.
- 사용자 테스트용 서버는 디버그 웹서버 대신 릴리즈 정적 서버를 우선 사용한다.
- 로컬 표준 포트는 유지:
  - 웹: `5301`
  - 백엔드: `5055`

### 표준 실행 절차
1. 릴리즈 웹 빌드:
   - `flutter build web --release --dart-define=GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID --dart-define=TRANSCRIPT_API_URL=http://127.0.0.1:5055`
2. 정적 서버 실행:
   - `python3 -m http.server 5301 --bind 127.0.0.1 --directory build/web`
3. OAuth origin 점검:
   - `http://localhost:5301`
   - `http://127.0.0.1:5301`

---

## 2026-02-06 Python 패키지 업그레이드 실패 기록 (filelock)

### 발생한 오류
- 명령어: `./.venv/bin/python -m pip install filelock==3.20.3`
- 오류: `No matching distribution found for filelock==3.20.3`

### 왜 발생했는가
- 현재 가상환경 Python 버전은 `3.9.6`이다.
- `filelock 3.20.x`는 `Requires-Python >=3.10` 제약이 있어 설치할 수 없다.

### 다시는 같은 실수를 하지 않기 위한 규칙
- 취약점 권장 버전을 적용하기 전, 대상 패키지의 Python 최소 버전을 먼저 확인한다.
- Python 3.9 환경에서는 해당 권장 버전이 불가하면:
  - 앱 런타임 의존성 취약점을 우선 해소하고
  - 도구/개발 의존성 잔여 취약점은 Python 3.10+ 마이그레이션 계획으로 처리한다.

### 표준 실행 절차
1. `./.venv/bin/python --version` 확인
2. `./.venv/bin/python -m pip index versions <package>`로 버전/호환성 확인
3. `./.venv/bin/pip-audit -r server/requirements.txt`로 런타임 취약점 우선 확인
