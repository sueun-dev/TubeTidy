MUST checklist

1) 운영 인프라 결정
   - 프론트 호스팅 (S3+CloudFront 또는 Vercel 등)
   - 백엔드 서버 (FastAPI: EC2/ECS 등)
   - DB (RDS Postgres)

2) 도메인/HTTPS 확정
   - 프론트 도메인
   - 백엔드 도메인
   - SSL 적용

3) Google OAuth 운영 설정
   - Authorized JavaScript origins에 운영 도메인 등록
   - OAuth Redirect URI 등록

4) 환경변수/시크릿 분리
   - OPENAI_API_KEY, DATABASE_URL 등 서버 환경변수로 관리
   - .env에 하드코딩된 키 제거/회수

5) DB 통합 테스트
   - 실제 DB 연결로 server/tests/test_db_integration.py 실행
   - 스키마 생성/삭제 가능한 계정 필요

6) 운영 품질
   - 로깅/에러 추적 (예: Sentry)
   - 백업/모니터링
   - CORS를 운영 도메인만 허용하도록 조정
