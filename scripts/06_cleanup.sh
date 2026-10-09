#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-us-central1}"
REPO_NAME="doc-pipeline"
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/processor:latest"

echo "=================================================="
echo "Cleaning Up Google Cloud Resources"
echo "Project: $PROJECT_ID"
echo "=================================================="

read -p "Are you sure you want to destroy all pipeline infrastructure? (y/N): " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# 1. Destroy Terraform provisioned resources
cd "$ROOT_DIR/terraform"
if [ -f "terraform.tfstate" ]; then
    echo "Destroying Terraform resources (GCS, PubSub, Cloud Run, BigQuery)..."
    terraform destroy -auto-approve \
        -var="project_id=${PROJECT_ID}" \
        -var="region=${REGION}" \
        -var="container_image=${IMAGE_TAG}"
fi

# 2. Delete Artifact Registry Repository (Optional)
read -p "Do you also want to delete the Artifact Registry repository '${REPO_NAME}'? (y/N): " delete_repo
if [[ "$delete_repo" == [yY] ]]; then
    echo "Deleting Artifact Registry repository..."
    gcloud artifacts repositories delete "$REPO_NAME" --location="$REGION" --project="$PROJECT_ID" --quiet || true
fi

echo "=================================================="
echo "Cleanup completed successfully!"
echo "=================================================="
