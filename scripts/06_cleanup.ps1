$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot

$ProjectId = $env:PROJECT_ID
if (-not $ProjectId) {
    $ProjectId = (gcloud config get-value project 2>$null).Trim()
}

$Region = if ($env:REGION) { $env:REGION } else { "us-central1" }
$RepoName = "doc-pipeline"
$ImageTag = "${Region}-docker.pkg.dev/${ProjectId}/${RepoName}/processor:latest"

Write-Host "=================================================="
Write-Host "Cleaning Up Google Cloud Resources"
Write-Host "Project: $ProjectId | Region: $Region"
Write-Host "=================================================="

$confirm = Read-Host "Are you sure you want to destroy all pipeline infrastructure? (y/N)"
if ($confirm -notmatch "^[yY]$") {
    Write-Host "Cleanup cancelled."
    exit 0
}

# 1. Destroy Terraform provisioned resources
Set-Location (Join-Path $RootDir "terraform")
if (Test-Path "terraform.tfstate") {
    Write-Host "Destroying Terraform resources (GCS, PubSub, Cloud Run, BigQuery)..."
    terraform destroy -auto-approve `
        -var="project_id=${ProjectId}" `
        -var="region=${Region}" `
        -var="container_image=${ImageTag}"
}

# 2. Delete Artifact Registry Repository (Optional)
$delRepo = Read-Host "Do you also want to delete the Artifact Registry repository '$RepoName'? (y/N)"
if ($delRepo -match "^[yY]$") {
    Write-Host "Deleting Artifact Registry repository..."
    gcloud artifacts repositories delete $RepoName --location=$Region --project=$ProjectId --quiet
}

Write-Host "=================================================="
Write-Host "Cleanup completed successfully!" -ForegroundColor Green
Write-Host "=================================================="
