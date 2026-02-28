#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-youtube-summary-prod-260209}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-youtube-summary-api}"
REPOSITORY="${REPOSITORY:-youtube-summary}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-youtube-summary-api-sa}"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${SERVICE_NAME}:${IMAGE_TAG}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

required_vars=(
  DATABASE_URL
  OPENAI_API_KEY
  CORS_ALLOWED_ORIGINS
)

for key in "${required_vars[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required env var: ${key}" >&2
    exit 1
  fi
done

if [[ -z "${GOOGLE_CLIENT_IDS:-}" ]] \
  && [[ -z "${GOOGLE_WEB_CLIENT_ID:-}" ]] \
  && [[ -z "${GOOGLE_IOS_CLIENT_ID:-}" ]]; then
  echo "Set GOOGLE_CLIENT_IDS or GOOGLE_WEB_CLIENT_ID/GOOGLE_IOS_CLIENT_ID" >&2
  exit 1
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet

if ! gcloud artifacts repositories describe "${REPOSITORY}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" >/dev/null 2>&1; then
  gcloud artifacts repositories create "${REPOSITORY}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --repository-format=docker \
    --description="YouTube Summary container images" \
    --quiet
fi

upsert_secret() {
  local name="$1"
  local value="$2"

  if ! gcloud secrets describe "${name}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud secrets create "${name}" \
      --project="${PROJECT_ID}" \
      --replication-policy=automatic \
      --quiet
  fi
  printf '%s' "${value}" | gcloud secrets versions add "${name}" \
    --project="${PROJECT_ID}" \
    --data-file=- \
    --quiet >/dev/null
}

OPENAI_SECRET_NAME="${OPENAI_SECRET_NAME:-youtube-summary-openai-api-key}"
DATABASE_SECRET_NAME="${DATABASE_SECRET_NAME:-youtube-summary-database-url}"

upsert_secret "${OPENAI_SECRET_NAME}" "${OPENAI_API_KEY}"
upsert_secret "${DATABASE_SECRET_NAME}" "${DATABASE_URL}"

if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="YouTube Summary API Runtime" \
    --quiet
fi

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet >/dev/null

ENV_VARS="APP_ENV=production|FAIL_CLOSED_WITHOUT_DB=true|BACKEND_REQUIRE_AUTH=true|CORS_ALLOWED_ORIGINS=${CORS_ALLOWED_ORIGINS}"
if [[ -n "${GOOGLE_CLIENT_IDS:-}" ]]; then
  ENV_VARS="${ENV_VARS}|GOOGLE_CLIENT_IDS=${GOOGLE_CLIENT_IDS}"
fi
if [[ -n "${GOOGLE_WEB_CLIENT_ID:-}" ]]; then
  ENV_VARS="${ENV_VARS}|GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID}"
fi
if [[ -n "${GOOGLE_IOS_CLIENT_ID:-}" ]]; then
  ENV_VARS="${ENV_VARS}|GOOGLE_IOS_CLIENT_ID=${GOOGLE_IOS_CLIENT_ID}"
fi

gcloud builds submit \
  --project="${PROJECT_ID}" \
  --tag "${IMAGE_URI}" \
  .

gcloud run deploy "${SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --platform=managed \
  --image="${IMAGE_URI}" \
  --allow-unauthenticated \
  --port=8080 \
  --cpu=1 \
  --memory=1Gi \
  --min-instances=0 \
  --max-instances=10 \
  --service-account="${SERVICE_ACCOUNT_EMAIL}" \
  --set-env-vars="^|^${ENV_VARS}" \
  --set-secrets="OPENAI_API_KEY=${OPENAI_SECRET_NAME}:latest,DATABASE_URL=${DATABASE_SECRET_NAME}:latest" \
  --quiet

SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format='value(status.url)')"

echo "Cloud Run deployed: ${SERVICE_URL}"
