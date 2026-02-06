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
