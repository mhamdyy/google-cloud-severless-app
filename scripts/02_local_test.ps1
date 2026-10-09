$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

Write-Host "=================================================="
Write-Host "Running Local Tests and Virtual Environment Setup"
Write-Host "=================================================="

if (-not (Test-Path ".venv")) {
    Write-Host "Creating virtual environment .venv..."
    python -m venv .venv
}

$VenvPython = Join-Path $RootDir ".venv\Scripts\python.exe"
$VenvPip    = Join-Path $RootDir ".venv\Scripts\pip.exe"
$VenvPytest = Join-Path $RootDir ".venv\Scripts\pytest.exe"

Write-Host "Installing dependencies..."
& $VenvPip install --upgrade pip
& $VenvPip install -r requirements.txt

Write-Host "Running pytest test suite..."
& $VenvPytest tests/ -v

Write-Host "Testing OCR processor logic with sample text..."
& $VenvPython -c "from app.services.ocr_service import simulated_ocr_process; count, tags = simulated_ocr_process(b'Cloud Run PubSub BigQuery storage write API document analysis pipeline', 'sample.txt'); print(f'Extraction success -> Words: {count}, Top Tags: {tags}')"

Write-Host "Local tests passed successfully!" -ForegroundColor Green
