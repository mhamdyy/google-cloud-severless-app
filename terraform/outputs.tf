output "storage_bucket_name" {
  description = "The created GCS bucket for uploading documents"
  value       = google_storage_bucket.input_bucket.name
}

output "pubsub_topic_name" {
  description = "The Pub/Sub topic receiving GCS upload notifications"
  value       = google_pubsub_topic.document_upload_topic.name
}

output "pubsub_dlq_topic_name" {
  description = "The Dead Letter Queue Pub/Sub topic"
  value       = google_pubsub_topic.dead_letter_topic.name
}

output "cloud_run_service_url" {
  description = "The URL of the deployed Cloud Run processor"
  value       = google_cloud_run_v2_service.processor.uri
}

output "bigquery_table" {
  description = "Full BigQuery table ID"
  value       = "${var.project_id}.${google_bigquery_dataset.document_pipeline.dataset_id}.${google_bigquery_table.document_metadata.table_id}"
}
