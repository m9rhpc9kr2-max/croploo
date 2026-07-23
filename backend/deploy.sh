#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="cultioo"
SERVICE="croploo-backend"
REGION="europe-west1"

echo "Deploying $SERVICE to Cloud Run ($PROJECT/$REGION)..."

gcloud run deploy "$SERVICE" \
  --source . \
  --project "$PROJECT" \
  --region "$REGION" \
  --platform managed \
  --add-cloudsql-instances cultioo:europe-west1:cultioo \
  --set-env-vars "CROPLOO_DB_SOCKET_PATH=/cloudsql/cultioo:europe-west1:cultioo,CROPLOO_DB_USER=kernex_app,CROPLOO_DB_NAME=croploo,SMTP_HOST=smtp.mailgun.org,SMTP_PORT=587,SMTP_USER=noreply@cultioo.com,MAIL_FROM=Croploo <noreply@cultioo.com>,APP_URL=https://croploo-backend-78230737866.europe-west1.run.app,FRED_API_KEY=ef088f1a5ec99a16aa762f60d24c5102,FMP_API_KEY=Ua6BPmutlFaV4asdZfcwWPHzIEkdchRM" \
  --set-secrets "CROPLOO_DB_PASSWORD=kernex-db-password:latest,CROPLOO_JWT_SECRET=kernex-jwt-secret:latest,STRIPE_SECRET_KEY=kernex-stripe-secret-key:latest,SMTP_PASS=kernex-smtp-pass:latest,ALPHA_VANTAGE_API_KEY=kernex-alphavantage-key:latest,ANTHROPIC_API_KEY=kernex-anthropic-api-key:latest,EIA_API_KEY=kernex-eia-api-key:latest,NASS_API_KEY=kernex-nass-api-key:latest,GEMINI_API_KEY=kernex-gemini-api-key:latest"

echo "Done."
