#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "Running Local Tests and Virtual Environment Setup"
echo "=================================================="

cd "$ROOT_DIR"

if [ ! -d ".venv" ]; then
    echo "Creating virtual environment .venv..."
    python -m venv .venv
fi

# Activate venv
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
elif [ -f ".venv/Scripts/activate" ]; then
    source .venv/Scripts/activate
fi

echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "Running pytest test suite..."
pytest tests/ -v

echo "Testing OCR processor logic with sample text..."
python -c "from app.services.ocr_service import simulated_ocr_process; count, tags = simulated_ocr_process(b'Cloud Run PubSub BigQuery storage write API document analysis pipeline', 'sample.txt'); print(f'Extraction success -> Words: {count}, Top Tags: {tags}')"

echo "Local tests passed successfully!"
