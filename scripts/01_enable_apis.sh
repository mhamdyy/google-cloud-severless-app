#!/usr/bin/env bash
set -euo pipefail

# Check for PROJECT_ID
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    echo "ERROR: GCP PROJECT_ID is not set. Run: export PROJECT_ID=your-project-id (or gcloud config set project your-project-id)"
    exit 1
fi

echo "=================================================="
echo "Enabling Required Google Cloud APIs for Project: ${PROJECT_ID}"
echo "=================================================="

gcloud services enable \
    run.googleapis.com \
    pubsub.googleapis.com \
    storage.googleapis.com \
    bigquery.googleapis.com \
    bigquerystorage.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    iam.googleapis.com \
    --project="${PROJECT_ID}"

echo "All required APIs successfully enabled!"
