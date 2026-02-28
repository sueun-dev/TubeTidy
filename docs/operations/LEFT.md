# LEFT - 퍼블릭 릴리즈 전 남은 작업

## 완료된 기반 (참고)
- [x] 백엔드 보안 리팩토링 반영 (JWKS 토큰 검증, 쓰기 엔드포인트 rate limit, fail-closed)
- [x] `flutter analyze` 통과
- [x] `flutter test` 통과
- [x] `./.venv/bin/python -m unittest server.tests.test_app` 통과
- [x] `DATABASE_URL` 주입 후 `./.venv/bin/python -m unittest server.tests.test_db_integration` 통과
- [x] GCP 프로젝트 생성: `youtube-summary-prod-260209`
- [x] Cloud Run 배포 기반 생성: API 활성화 + Artifact Registry(`us-central1/youtube-summary`)
- [x] 배포 파일 추가: `Dockerfile`, `.dockerignore`, `scripts/deploy_cloud_run.sh`
- [x] Cloud Run 서비스 배포 완료: `youtube-summary-api` (`us-central1`)
- [x] Cloud SQL(PostgreSQL 15) 생성: `youtube-summary-pg` + DB `youtube_summary` + 앱 계정 `youtube_summary_app`
- [x] Cloud Run-Cloud SQL 연결 적용(`--add-cloudsql-instances`) 및 `/health` 확인(`db_ok=true`)
- [x] Uptime 체크 + 알림 정책 생성 완료

## 인프라 상태 메모
- [x] `youtube-summary-prod-260209` 프로젝트에 billing 연결 완료
- [ ] 기존 `nano-banana-hackaton` 프로젝트 billing 재연결 필요 시 별도 처리
- [x] 현재 서비스 URL: `https://youtube-summary-api-iqwbnpowza-uc.a.run.app`
- [x] Secret Manager 최신값 반영: `youtube-summary-database-url`(Cloud SQL 소켓 URL), `youtube-summary-openai-api-key`
- [x] 현재 배포 리비전: `youtube-summary-api-00005-52j`
- [ ] 모니터링 이메일 채널(`sueun.dev@gmail.com`) 수신 확인/검증 완료 여부 최종 확인 필요

## P0 - 공개 릴리즈 전에 반드시 완료
- [ ] 노출된 시크릿 전부 즉시 교체(회전): `OPENAI_API_KEY`, 기타 OAuth/서버 키 (DB 비밀번호는 회전 완료)
- [x] 배포 환경 Secret Manager에만 저장 (`.env` 파일 그대로 배포 금지)
- [x] 프로덕션 환경변수 최종 확정/적용
- [x] `APP_ENV=production` 설정
- [x] `FAIL_CLOSED_WITHOUT_DB=true` 설정
- [x] `BACKEND_REQUIRE_AUTH=true` 설정
- [x] `DATABASE_URL` 설정 (Managed PostgreSQL/Cloud SQL)
- [x] `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` 서버 환경변수 설정
- [x] `CORS_ALLOWED_ORIGINS` 제한 적용 (모바일 네이티브 앱 전용 출시에서는 기능상 비필수, 현재 보수적으로 단일 origin만 허용)
- [x] DB 접근 네트워크 제한 (Cloud SQL + IAM 기반 연결)
- [x] 백엔드 HTTPS(Cloud Run 기본 TLS) 적용 및 인증서 점검
- [x] `/health` 기반 uptime 모니터링 + 장애 알림 연결

## P0 - App Store 심사 필수
- [ ] App Store Connect `App Privacy` 항목 실제 데이터 흐름 기준으로 작성
- [ ] 개인정보처리방침 URL, 이용약관 URL 운영 링크로 교체
- [ ] 앱 내 계정 삭제 경로 제공 여부 최종 점검 (계정 기능이 있으면 필수)
- [ ] Google 로그인만 제공 시 Sign in with Apple 요구사항(가이드 4.8) 점검 및 필요시 추가
- [ ] 심사용 Review Notes 작성 (로그인/핵심 기능 재현 방법 포함)

## P1 - 릴리즈 직전 품질/보안 검증
- [ ] 스테이징에서 E2E 스모크: 로그인 -> 구독 동기화 -> 요약 -> 보관 -> 선택 저장
- [ ] rate limit 동작 확인(429 응답/복구)
- [ ] DB 중단 시나리오에서 fail-closed(503) 동작 확인
- [ ] 서버 로그 민감정보(토큰/키/개인정보) 노출 여부 점검
- [ ] iOS Release 빌드 + TestFlight 외부 테스터 검증

## P1 - 런칭 직후 운영 준비
- [ ] 에러 모니터링(Sentry/Cloud Logging 등) 연결
- [ ] DB 백업/복구 리허설 1회 수행
- [ ] 시크릿 정기 회전 주기 수립
- [ ] 장애 대응 Runbook 문서화

## 바로 실행용 체크 커맨드
- [x] `flutter analyze`
- [x] `flutter test`
- [x] `./.venv/bin/python -m unittest server.tests.test_app`
- [x] `DATABASE_URL='postgresql+psycopg2://USER:PASS@HOST:5432/DB' ./.venv/bin/python -m unittest server.tests.test_db_integration`
