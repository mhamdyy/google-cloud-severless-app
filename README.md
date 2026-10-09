# Serverless Event-Driven Document Processing Pipeline on Google Cloud

A production-grade, event-driven serverless pipeline on Google Cloud that ingests documents from Cloud Storage, triggers an OCR & metadata extraction processor on Cloud Run via Pub/Sub Push (with OIDC authentication & DLQ), and streams structured metadata directly into BigQuery using the BigQuery Storage Write API.

## Architecture

```
User / Client
      │
      ▼ (Upload document)
Cloud Storage Bucket
      │
      ▼ (OBJECT_FINALIZE notification)
Pub/Sub Ingestion Topic  ───────── (Persistent Failures) ──► Dead Letter Queue (DLQ)
      │
      ▼ (Authenticated Push with OIDC)
Cloud Run Processor (FastAPI)
      ├── 1. Downloads document from GCS
      ├── 2. Runs simulated OCR & keyword tag extraction
      └── 3. Streams record into BigQuery
            │
            ▼
      BigQuery Dataset & Table (via Storage Write API)
```

---

## Directory Structure

```
├── app/
│   ├── config.py                  # Environment & project configuration
│   ├── main.py                    # FastAPI app & Pub/Sub push webhook
│   ├── schemas.py                 # Pydantic schemas (PubSub message, metadata)
│   ├── proto/
│   │   ├── document_metadata.proto # Protobuf definition for BigQuery Storage Write API
│   │   └── document_metadata_pb2.py# Compiled protobuf module
│   └── services/
│       ├── gcp_service.py         # GCS & BigQuery Storage Write API services
│       └── ocr_service.py         # Simulated OCR and tag extraction logic
├── terraform/
│   ├── main.tf                    # GCS, Pub/Sub, DLQ, BigQuery, IAM & Cloud Run
│   ├── variables.tf               # Terraform input variables
│   └── outputs.tf                 # Exported resource identifiers
├── tests/
│   └── test_main.py               # Unit tests covering endpoints & mock GCP flows
├── Dockerfile                     # Cloud Run container definition
└── requirements.txt               # Application dependencies
```

---

## Quickstart & Local Testing

### 1. Run Unit Tests Locally

Install dependencies:
```bash
pip install -r requirements.txt
```

Run tests with `pytest`:
```bash
pytest tests/
```

### 2. Run the Service Locally

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

---

## Deploying to Google Cloud

### Prerequisites
- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) authenticated.
- [Terraform](https://developer.hashicorp.com/terraform/downloads) installed.
- Enabled APIs:
  ```bash
  gcloud services enable \
    run.googleapis.com \
    pubsub.googleapis.com \
    storage.googleapis.com \
    bigquery.googleapis.com \
    bigquerystorage.googleapis.com \
    artifactregistry.googleapis.com
  ```

### Step 1: Build & Push Container to Google Artifact Registry

```bash
# 1. Create Artifact Registry repository
gcloud artifacts repositories create doc-pipeline \
    --repository-format=docker \
    --location=us-central1

# 2. Build and submit container image with Cloud Build
gcloud builds submit --tag us-central1-docker.pkg.dev/YOUR_PROJECT_ID/doc-pipeline/processor:latest .
```

### Step 2: Provision Infrastructure with Terraform

```bash
cd terraform

terraform init

terraform apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="region=us-central1" \
  -var="container_image=us-central1-docker.pkg.dev/YOUR_PROJECT_ID/doc-pipeline/processor:latest"
```

### Step 3: Test End-to-End Ingestion

Upload a sample text document to your newly created bucket:
```bash
# Get the bucket name from Terraform output
BUCKET_NAME=$(terraform output -raw storage_bucket_name)

# Upload sample file
gsutil cp sample.txt gs://${BUCKET_NAME}/sample.txt
```

Verify the record appeared in BigQuery:
```bash
bq query --use_legacy_sql=false \
  'SELECT filename, word_count, tags, status, processed_time FROM `YOUR_PROJECT_ID.document_processing.document_metadata`'
```
