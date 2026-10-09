$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot

$ProjectId = $env:PROJECT_ID
if (-not $ProjectId) {
    $ProjectId = (gcloud config get-value project 2>$null).Trim()
}

$Region = if ($env:REGION) { $env:REGION } else { "us-central1" }
$RepoName = "doc-pipeline"
$ImageTag = "${Region}-docker.pkg.dev/${ProjectId}/${RepoName}/processor:latest"

if (-not $ProjectId -or $ProjectId -eq "(unset)") {
    Write-Error "GCP PROJECT_ID is not set. Set with: `$env:PROJECT_ID='your-project-id'"
}

Write-Host "=================================================="
Write-Host "Deploying Serverless Pipeline to Google Cloud"
Write-Host "Project: $ProjectId | Region: $Region"
Write-Host "=================================================="

# 1. Create Artifact Registry repository if not exists
Write-Host "Checking / creating Artifact Registry repository: $RepoName..."
$repoCheck = gcloud artifacts repositories describe $RepoName --location=$Region --project=$ProjectId 2>&1
if ($LASTEXITCODE -ne 0) {
    gcloud artifacts repositories create $RepoName `
        --repository-format=docker `
        --location=$Region `
        --description="Repository for serverless document processor" `
        --project=$ProjectId
}

# 2. Build and submit container via Cloud Build
Write-Host "Building and submitting container image via Cloud Build: $ImageTag..."
Set-Location $RootDir
gcloud builds submit --tag $ImageTag --project=$ProjectId .

# 3. Deploy infrastructure via Terraform
Write-Host "Deploying infrastructure via Terraform..."
Set-Location (Join-Path $RootDir "terraform")

terraform init

terraform apply -auto-approve `
    -var="project_id=${ProjectId}" `
    -var="region=${Region}" `
    -var="container_image=${ImageTag}"

Write-Host "=================================================="
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "=================================================="
terraform output
