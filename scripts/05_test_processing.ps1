$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot

Write-Host "=================================================="
Write-Host "Testing Direct Processing Webhook Endpoint"
Write-Host "=================================================="

Set-Location (Join-Path $RootDir "terraform")

$ServiceUrl = (terraform output -raw cloud_run_service_url 2>$null).Trim()
$BucketName = (terraform output -raw storage_bucket_name 2>$null).Trim()

if (-not $ServiceUrl) {
    Write-Host "Service URL not found in terraform output. Testing against local server http://localhost:8080..."
    $ServiceUrl = "http://localhost:8080"
    $BucketName = "my-doc-bucket"
}

$Timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$TestDoc   = "direct_test_$Timestamp.txt"

$GcsJson = @{
    bucket      = $BucketName
    name        = $TestDoc
    timeCreated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json -Compress

$B64Data = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($GcsJson))

$Payload = @{
    message = @{
        data = $B64Data
        attributes = @{
            eventType = "OBJECT_FINALIZE"
            bucketId  = $BucketName
            objectId  = $TestDoc
        }
        messageId = "mock-test-id-$Timestamp"
    }
} | ConvertTo-Json -Depth 5

$Headers = @{
    "Content-Type" = "application/json"
}

if ($ServiceUrl -like "*run.app*") {
    $IdToken = (gcloud auth print-identity-token 2>$null).Trim()
    if ($IdToken) {
        $Headers["Authorization"] = "Bearer $IdToken"
    }
}

Write-Host "Sending mock Pub/Sub push notification to $ServiceUrl/pubsub/process..."
try {
    $response = Invoke-RestMethod -Uri "$ServiceUrl/pubsub/process" -Method Post -Headers $Headers -Body $Payload
    Write-Host "Response received:" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 5
} catch {
    Write-Host "Request completed with status/error: $_"
}
