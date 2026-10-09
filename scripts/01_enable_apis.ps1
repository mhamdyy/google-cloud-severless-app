$ErrorActionPreference = "Stop"

$ProjectId = $env:PROJECT_ID
if (-not $ProjectId) {
    $ProjectId = (gcloud config get-value project 2>$null).Trim()
}

if (-not $ProjectId -or $ProjectId -eq "(unset)") {
    Write-Error "GCP PROJECT_ID is not set. Set with: `$env:PROJECT_ID='your-project-id' (or gcloud config set project your-project-id)"
}

Write-Host "=================================================="
Write-Host "Enabling Required Google Cloud APIs for: $ProjectId"
Write-Host "=================================================="

gcloud services enable `
    run.googleapis.com `
    pubsub.googleapis.com `
    storage.googleapis.com `
    bigquery.googleapis.com `
    bigquerystorage.googleapis.com `
    artifactregistry.googleapis.com `
    cloudbuild.googleapis.com `
    iam.googleapis.com `
    --project=$ProjectId

Write-Host "All required APIs successfully enabled!" -ForegroundColor Green
