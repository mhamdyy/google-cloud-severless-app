#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "End-to-End Pipeline Verification Test"
echo "=================================================="

cd "$ROOT_DIR/terraform"

BUCKET_NAME=$(terraform output -raw storage_bucket_name 2>/dev/null || true)
BIGQUERY_TABLE=$(terraform output -raw bigquery_table 2>/dev/null || true)

if [ -z "$BUCKET_NAME" ]; then
    echo "ERROR: Unable to get storage_bucket_name from terraform output. Did you run deploy first?"
    exit 1
fi

TEST_FILE="test_document_$(date +%s).txt"
echo "This is a confidential business proposal for cloud serverless architecture including BigQuery and PubSub data pipelines." > "/tmp/${TEST_FILE}"

echo "1. Uploading test file to gs://${BUCKET_NAME}/${TEST_FILE}..."
gcloud storage cp "/tmp/${TEST_FILE}" "gs://${BUCKET_NAME}/${TEST_FILE}"

echo "2. Waiting 15 seconds for event propagation and Cloud Run processing..."
sleep 15

echo "3. Querying BigQuery table: ${BIGQUERY_TABLE}..."
bq query --use_legacy_sql=false \
    "SELECT filename, word_count, tags, status, processed_time FROM \`${BIGQUERY_TABLE}\` WHERE filename = '${TEST_FILE}'"

echo "4. Checking recent Cloud Run execution logs..."
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="document-processor"' \
    --limit=10 \
    --format="table(timestamp, textPayload)"

echo "End-to-end test completed successfully!"
