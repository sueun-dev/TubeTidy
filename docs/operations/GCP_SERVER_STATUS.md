# GCP Server Status (YouTube Summary)

마지막 갱신: 2026-02-09 20:11:00 UTC (2026-02-09 15:11:00 EST)

## 1) GCP 프로젝트 / 계정
- GCP 프로젝트 ID: `youtube-summary-prod-260209`
- 프로젝트 번호: `539229132302`
- 프로젝트 이름: `youtube-summary-prod`
- 프로젝트 생성 시각: `2026-02-09T03:10:22.631611Z`
- Billing 계정: `billingAccounts/01E73E-FF855A-0CF3B6` (연결됨)
- 현재 gcloud 계정: `sueun.dev@gmail.com`
- 참고: 로컬 gcloud 기본 프로젝트는 현재 `coin-helio`로 설정되어 있으므로, 명령 실행 시 `--project youtube-summary-prod-260209`를 항상 명시 권장

## 2) 서버(Cloud Run) 정보
- 서비스명: `youtube-summary-api`
- 리전: `us-central1`
- 현재 URL: `https://youtube-summary-api-iqwbnpowza-uc.a.run.app`
- 트래픽: 최신 리비전 100%
- 최신 리비전: `youtube-summary-api-00005-52j`
- 런타임 서비스 계정: `youtube-summary-api-sa@youtube-summary-prod-260209.iam.gserviceaccount.com`
- 컨테이너 이미지:
  - `us-central1-docker.pkg.dev/youtube-summary-prod-260209/youtube-summary/youtube-summary-api:prod-20260208-223529`
- 리소스 제한:
  - CPU: `1`
  - Memory: `1Gi`
  - Timeout: `600s`
  - Max scale: `10`
- Cloud SQL 연결 어노테이션:
  - `run.googleapis.com/cloudsql-instances: youtube-summary-prod-260209:us-central1:youtube-summary-pg`
- 공개 접근:
  - `roles/run.invoker`에 `allUsers` 바인딩됨 (퍼블릭 호출 가능)

### 서버 환경변수(중요)
- `APP_ENV=production`
- `FAIL_CLOSED_WITHOUT_DB=true`
- `BACKEND_REQUIRE_AUTH=true`
- `CORS_ALLOWED_ORIGINS=https://youtube-summary-api-iqwbnpowza-uc.a.run.app`
- `GOOGLE_WEB_CLIENT_ID` 설정됨
- `GOOGLE_IOS_CLIENT_ID` 설정됨
- `OPENAI_API_KEY`는 Secret Manager 참조
- `DATABASE_URL`은 Secret Manager 참조

### 헬스체크
- 엔드포인트: `GET /health`
- 현재 응답: `{"status":"ok","db_enabled":true,"db_ok":true}`

## 3) DB(Cloud SQL PostgreSQL) 정보
- 인스턴스명: `youtube-summary-pg`
- 엔진: `POSTGRES_15`
- 상태: `RUNNABLE`
- 리전/존: `us-central1` / `us-central1-c`
- Tier: `db-custom-1-3840`
- 가용성: `ZONAL`
- 연결명(Connection Name):
  - `youtube-summary-prod-260209:us-central1:youtube-summary-pg`
- DB 목록:
  - `postgres`
  - `youtube_summary`
- DB 사용자:
  - `postgres`
  - `youtube_summary_app`
- IP:
  - Primary: `34.31.59.102`
  - Outgoing: `35.192.135.128`

## 4) 시크릿(Secret Manager)
- `youtube-summary-database-url`
  - 버전: `1,2,3,4` (모두 enabled)
- `youtube-summary-openai-api-key`
  - 버전: `1,2,3` (모두 enabled)
- 주의:
  - 값 자체는 문서/로그/코드에 기록 금지
  - 키 회전 시 새 버전 추가 후 서비스 재검증 권장

## 5) 이미지/배포 파이프라인
- Artifact Registry 리포지토리:
  - 이름: `youtube-summary`
  - 형식: `DOCKER`
  - 위치: `us-central1`
- 등록 이미지(최근):
  - digest `sha256:90fc...e9ac`, tag `prod-20260208-223529`
  - digest `sha256:5892...88b9`, tag `bootstrap-20260208-222426`
- Cloud Build 최근 성공 이력:
  - `80533eff-66b5-4ac5-a8b5-b05364831769` (prod 이미지)
  - `a38833a9-c40c-48f4-b623-301172ef7ef4` (bootstrap 이미지)

## 6) 모니터링/알림
- Uptime Check:
  - 이름: `projects/youtube-summary-prod-260209/uptimeCheckConfigs/youtube-summary-api-health-xSxGHcCpVLk`
  - 대상: `https://youtube-summary-api-iqwbnpowza-uc.a.run.app/health`
  - 주기/타임아웃: `60s / 10s`
- Notification Channel:
  - 이름: `projects/youtube-summary-prod-260209/notificationChannels/10499049925849490990`
  - 타입: `email`
  - 대상 이메일: `sueun.dev@gmail.com`
- Alert Policy:
  - 이름: `projects/youtube-summary-prod-260209/alertPolicies/9167099976719618381`
  - 표시명: `youtube-summary-api-uptime-alert`
  - 상태: enabled

## 7) IAM(런타임 서비스 계정)
- 서비스 계정:
  - `youtube-summary-api-sa@youtube-summary-prod-260209.iam.gserviceaccount.com`
- 프로젝트 역할:
  - `roles/cloudsql.client`
  - `roles/secretmanager.secretAccessor`

## 8) 현재 레포의 관련 파일
- 배포 스크립트: `scripts/deploy_cloud_run.sh`
- 컨테이너 파일: `Dockerfile`
- 컨테이너 제외 규칙: `.dockerignore`
- 릴리즈 체크리스트: `LEFT.md`

## 9) 운영 시 빠른 점검 명령
```bash
gcloud run services describe youtube-summary-api \
  --project youtube-summary-prod-260209 --region us-central1 \
  --format='value(status.latestReadyRevisionName,status.url)'

curl -sS https://youtube-summary-api-iqwbnpowza-uc.a.run.app/health

gcloud sql instances describe youtube-summary-pg \
  --project youtube-summary-prod-260209 --format='value(state,connectionName)'

gcloud monitoring uptime list-configs \
  --project youtube-summary-prod-260209
```

## 10) 남은 핵심 TODO(요약)
- OpenAI/OAuth 키 회전 최종 완료
- App Store 제출 메타데이터(App Privacy, 정책 URL, Review Notes) 확정
- 모니터링 이메일 수신 테스트 1회 수행
