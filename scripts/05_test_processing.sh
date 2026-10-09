#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "Testing Direct Processing Webhook Endpoint"
echo "=================================================="

cd "$ROOT_DIR/terraform"

SERVICE_URL=$(terraform output -raw cloud_run_service_url 2>/dev/null || true)
BUCKET_NAME=$(terraform output -raw storage_bucket_name 2>/dev/null || true)

if [ -z "$SERVICE_URL" ]; then
    echo "Service URL not found from terraform output. Testing against local server http://localhost:8080..."
    SERVICE_URL="http://localhost:8080"
    BUCKET_NAME="my-doc-bucket"
fi

TEST_DOC="direct_test_$(date +%s).txt"

# Create a mock base64 PubSub payload
GCS_JSON=$(cat <<EOF
{"bucket": "${BUCKET_NAME}", "name": "${TEST_DOC}", "timeCreated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}
EOF
)
B64_DATA=$(echo -n "$GCS_JSON" | base64)

PAYLOAD=$(cat <<EOF
{
  "message": {
    "data": "${B64_DATA}",
    "attributes": {
      "eventType": "OBJECT_FINALIZE",
      "bucketId": "${BUCKET_NAME}",
      "objectId": "${TEST_DOC}"
    },
    "messageId": "mock-test-id-$(date +%s)"
  }
}
EOF
)

echo "Sending mock Pub/Sub push notification to ${SERVICE_URL}/pubsub/process..."

# Obtain OIDC identity token if targeting Cloud Run
AUTH_HEADER=""
if [[ "$SERVICE_URL" == *"run.app"* ]]; then
    ID_TOKEN=$(gcloud auth print-identity-token 2>/dev/null || true)
    if [ -n "$ID_TOKEN" ]; then
        AUTH_HEADER="Authorization: Bearer ${ID_TOKEN}"
    fi
fi

if [ -n "$AUTH_HEADER" ]; then
    curl -X POST "${SERVICE_URL}/pubsub/process" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "$PAYLOAD"
else
    curl -X POST "${SERVICE_URL}/pubsub/process" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD"
fi

echo ""
echo "Direct webhook test dispatched!"
