import base64
import json
import pytest
from fastapi.testclient import TestClient

from app.main import app, storage_service, bq_writer_service

client = TestClient(app)

class MockStorageClient:
    def __init__(self, sample_files=None):
        self.sample_files = sample_files or {}

    def download_file(self, bucket_name: str, object_name: str) -> bytes:
        key = f"{bucket_name}/{object_name}"
        if key in self.sample_files:
            return self.sample_files[key]
        raise FileNotFoundError(f"Object {object_name} not found")

class MockBigQueryWriter:
    def __init__(self):
        self.records = []

    def append_document_record(self, record_dict):
        self.records.append(record_dict)

@pytest.fixture(autouse=True)
def setup_mocks(monkeypatch):
    mock_storage = MockStorageClient({
        "my-doc-bucket/sample_contract.txt": b"Confidential business agreement between Party A and Party B regarding software services.",
        "my-doc-bucket/image.png": b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
    })
    mock_bq = MockBigQueryWriter()

    monkeypatch.setattr(storage_service, "download_file", mock_storage.download_file)
    monkeypatch.setattr(bq_writer_service, "append_document_record", mock_bq.append_document_record)

def test_health_check():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_process_text_file_upload():
    raw_data = json.dumps({
        "bucket": "my-doc-bucket",
        "name": "sample_contract.txt",
        "timeCreated": "2026-10-09T12:00:00Z"
    }).encode("utf-8")
    
    b64_data = base64.b64encode(raw_data).decode("utf-8")

    payload = {
        "message": {
            "data": b64_data,
            "attributes": {
                "eventType": "OBJECT_FINALIZE",
                "bucketId": "my-doc-bucket",
                "objectId": "sample_contract.txt"
            },
            "messageId": "msg-12345"
        }
    }

    response = client.post("/pubsub/process", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    record = data["record"]
    assert record["filename"] == "sample_contract.txt"
    assert record["word_count"] > 0
    assert "party" in record["tags"] or "agreement" in record["tags"]

def test_process_binary_file_upload():
    payload = {
        "message": {
            "attributes": {
                "eventType": "OBJECT_FINALIZE",
                "bucketId": "my-doc-bucket",
                "objectId": "image.png"
            },
            "messageId": "msg-67890"
        }
    }

    response = client.post("/pubsub/process", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["record"]["filename"] == "image.png"
    assert data["record"]["word_count"] > 0

def test_skip_non_finalize_events():
    payload = {
        "message": {
            "attributes": {
                "eventType": "OBJECT_DELETE",
                "bucketId": "my-doc-bucket",
                "objectId": "sample_contract.txt"
            }
        }
    }
    response = client.post("/pubsub/process", json=payload)
    assert response.status_code == 200
    assert response.json()["status"] == "ignored"

def test_missing_file_skips_without_error():
    payload = {
        "message": {
            "attributes": {
                "eventType": "OBJECT_FINALIZE",
                "bucketId": "my-doc-bucket",
                "objectId": "missing.txt"
            }
        }
    }
    response = client.post("/pubsub/process", json=payload)
    assert response.status_code == 200
    assert response.json()["status"] == "skipped"
