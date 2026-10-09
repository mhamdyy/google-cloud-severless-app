#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-us-central1}"
REPO_NAME="doc-pipeline"
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/processor:latest"

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    echo "ERROR: GCP PROJECT_ID is not set. Run: export PROJECT_ID=your-project-id"
    exit 1
fi

echo "=================================================="
echo "Deploying Serverless Pipeline to Google Cloud"
echo "Project: $PROJECT_ID | Region: $REGION"
echo "=================================================="

# 1. Create Artifact Registry repository if it doesn't exist
echo "Checking / creating Artifact Registry repository: $REPO_NAME..."
gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1 || \
gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Repository for serverless document processor" \
    --project="$PROJECT_ID"

# 2. Build and submit container image via Cloud Build
echo "Building and submitting container image via Cloud Build: $IMAGE_TAG..."
cd "$ROOT_DIR"
gcloud builds submit --tag "$IMAGE_TAG" --project="$PROJECT_ID" .

# 3. Deploy infrastructure via Terraform
echo "Deploying infrastructure via Terraform..."
cd "$ROOT_DIR/terraform"

terraform init

terraform apply -auto-approve \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="container_image=${IMAGE_TAG}"

echo "=================================================="
echo "Deployment Complete!"
echo "=================================================="
terraform output
