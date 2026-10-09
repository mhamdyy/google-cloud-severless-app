terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.20"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------
# 1. Cloud Storage Bucket for Ingestion
# -----------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "input_bucket" {
  name                        = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

# -----------------------------------------------------------
# 2. Pub/Sub Topics: Main Ingestion & Dead Letter Queue
# -----------------------------------------------------------
resource "google_pubsub_topic" "dead_letter_topic" {
  name = "document-processing-dlq"
}

resource "google_pubsub_topic" "document_upload_topic" {
  name = "document-upload-events"
}

# Allow GCS to publish to the Pub/Sub topic
data "google_storage_project_service_account" "gcs_account" {
}

resource "google_pubsub_topic_iam_member" "gcs_publisher" {
  topic  = google_pubsub_topic.document_upload_topic.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

# Configure GCS Notification to Pub/Sub on upload
resource "google_storage_notification" "upload_notification" {
  bucket         = google_storage_bucket.input_bucket.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.document_upload_topic.id
  event_types    = ["OBJECT_FINALIZE"]

  depends_on = [google_pubsub_topic_iam_member.gcs_publisher]
}

# -----------------------------------------------------------
# 3. BigQuery Dataset & Metadata Table
# -----------------------------------------------------------
resource "google_bigquery_dataset" "document_pipeline" {
  dataset_id  = var.bq_dataset_id
  description = "Dataset holding extracted document metadata"
  location    = var.region
}

resource "google_bigquery_table" "document_metadata" {
  dataset_id          = google_bigquery_dataset.document_pipeline.dataset_id
  table_id            = var.bq_table_id
  deletion_protection = false

  schema = jsonencode([
    { name = "filename", type = "STRING", mode = "REQUIRED", description = "Name of the uploaded file" },
    { name = "bucket", type = "STRING", mode = "REQUIRED", description = "Source GCS bucket" },
    { name = "upload_time", type = "TIMESTAMP", mode = "REQUIRED", description = "Time the document was uploaded" },
    { name = "processed_time", type = "TIMESTAMP", mode = "REQUIRED", description = "Time processing completed" },
    { name = "word_count", type = "INT64", mode = "REQUIRED", description = "Extracted word count" },
    { name = "tags", type = "STRING", mode = "REPEATED", description = "Top keyword tags" },
    { name = "file_size_bytes", type = "INT64", mode = "REQUIRED", description = "File size in bytes" },
    { name = "status", type = "STRING", mode = "REQUIRED", description = "Processing status" }
  ])
}

# -----------------------------------------------------------
# 4. Service Account for Cloud Run Processor
# -----------------------------------------------------------
resource "google_service_account" "cloud_run_sa" {
  account_id   = "document-processor-sa"
  display_name = "Cloud Run Document Processor Service Account"
}

# Cloud Run SA permissions: read GCS & write BigQuery (Storage Write API)
resource "google_storage_bucket_iam_member" "gcs_reader" {
  bucket = google_storage_bucket.input_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "bq_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# BigQuery Storage Write API User Role
resource "google_project_iam_member" "bq_storage_writer" {
  project = var.project_id
  role    = "roles/bigquery.admin" # or roles/bigquery.openSession / write roles
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# -----------------------------------------------------------
# 5. Cloud Run Service
# -----------------------------------------------------------
resource "google_cloud_run_v2_service" "processor" {
  name     = "document-processor"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloud_run_sa.email

    containers {
      image = var.container_image

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "BQ_DATASET"
        value = var.bq_dataset_id
      }
      env {
        name  = "BQ_TABLE"
        value = var.bq_table_id
      }
      env {
        name  = "ENVIRONMENT"
        value = "production"
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    }
  }
}

# -----------------------------------------------------------
# 6. Service Account & Push Subscription for Pub/Sub
# -----------------------------------------------------------
resource "google_service_account" "pubsub_invoker_sa" {
  account_id   = "pubsub-cloud-run-invoker"
  display_name = "PubSub Cloud Run Invoker SA"
}

# Grant pubsub_invoker_sa run.invoker permission on the Cloud Run service
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pubsub_invoker_sa.email}"
}

# Push Subscription with OIDC & Dead Letter Policy
resource "google_pubsub_subscription" "cloud_run_push" {
  name  = "document-upload-push-sub"
  topic = google_pubsub_topic.document_upload_topic.name

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.processor.uri}/pubsub/process"

    oidc_token {
      service_account_email = google_service_account.pubsub_invoker_sa.email
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  depends_on = [google_cloud_run_v2_service_iam_member.invoker]
}
