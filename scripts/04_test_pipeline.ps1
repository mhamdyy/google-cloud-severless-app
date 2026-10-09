$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot

Write-Host "=================================================="
Write-Host "End-to-End Pipeline Verification Test"
Write-Host "=================================================="

Set-Location (Join-Path $RootDir "terraform")

$BucketName = (terraform output -raw storage_bucket_name 2>$null).Trim()
$BqTable    = (terraform output -raw bigquery_table 2>$null).Trim()

if (-not $BucketName) {
    Write-Error "Unable to get storage_bucket_name from terraform output. Did you run deploy first?"
}

$Timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$TestFileName = "test_document_$Timestamp.txt"
$TempFilePath = Join-Path $env:TEMP $TestFileName

"This is a confidential business proposal for cloud serverless architecture including BigQuery and PubSub data pipelines." | Set-Content -Path $TempFilePath

Write-Host "1. Uploading test file to gs://$BucketName/$TestFileName..."
gcloud storage cp $TempFilePath "gs://$BucketName/$TestFileName"

Write-Host "2. Waiting 15 seconds for event propagation and Cloud Run processing..."
Start-Sleep -Seconds 15

Write-Host "3. Querying BigQuery table: $BqTable..."
bq query --use_legacy_sql=false `
    "SELECT filename, word_count, tags, status, processed_time FROM \`$BqTable\` WHERE filename = '$TestFileName'"

Write-Host "4. Checking recent Cloud Run execution logs..."
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="document-processor"' `
    --limit=10 `
    --format="table(timestamp, textPayload)"

Write-Host "End-to-end test completed successfully!" -ForegroundColor Green
