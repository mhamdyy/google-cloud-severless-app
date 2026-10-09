variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region for resources"
  type        = string
  default     = "us-central1"
}

variable "bucket_prefix" {
  description = "Prefix for the documents storage bucket"
  type        = string
  default     = "doc-ingest"
}

variable "bq_dataset_id" {
  description = "BigQuery dataset ID"
  type        = string
  default     = "document_processing"
}

variable "bq_table_id" {
  description = "BigQuery table ID for document metadata"
  type        = string
  default     = "document_metadata"
}

variable "container_image" {
  description = "Container image URI for Cloud Run service (e.g. gcr.io/PROJECT_ID/document-processor:latest or Artifact Registry)"
  type        = string
}
