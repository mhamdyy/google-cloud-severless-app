import base64
import json
import logging
from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import JSONResponse

from app.schemas import PubSubPushPayload, DocumentMetadata
from app.services.ocr_service import simulated_ocr_process
from app.services.gcp_service import StorageService, BigQueryWriterService

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Serverless Document Processing Service",
    description="Processes GCS file upload notifications via Pub/Sub and streams metadata into BigQuery.",
    version="1.0.0"
)

storage_service = StorageService()
bq_writer_service = BigQueryWriterService()

@app.get("/")
def health_check():
    return {"status": "healthy", "service": "document-processor"}

@app.post("/pubsub/process", status_code=status.HTTP_200_OK)
async def process_pubsub_message(payload: PubSubPushPayload):
    """
    Receives Pub/Sub push notification for GCS object finalization (upload).
    Cloud Storage notifications send metadata in payload.message.data (base64 encoded JSON)
    or in attributes (bucketId, objectId).
    """
    message = payload.message
    if not message:
        logger.error("Missing message body in Pub/Sub payload")
        raise HTTPException(status_code=400, detail="Invalid Pub/Sub payload: missing message")

    bucket_name = None
    object_name = None
    upload_time = None

    # Check GCS event attributes first
    if message.attributes:
        bucket_name = message.attributes.get("bucketId")
        object_name = message.attributes.get("objectId")
        event_type = message.attributes.get("eventType")
        
        # Only process object creation/finalization
        if event_type and event_type not in ("OBJECT_FINALIZE", "google.storage.object.finalize"):
            logger.info("Ignoring non-creation event type: %s", event_type)
            return {"status": "ignored", "reason": f"unhandled event type {event_type}"}

    # If not fully resolved from attributes, decode message data JSON
    if (not bucket_name or not object_name) and message.data:
        try:
            decoded_bytes = base64.b64decode(message.data)
            gcs_data = json.loads(decoded_bytes.decode("utf-8"))
            bucket_name = bucket_name or gcs_data.get("bucket")
            object_name = object_name or gcs_data.get("name")
            upload_time = gcs_data.get("timeCreated")
        except Exception as e:
            logger.error("Failed to decode message data: %s", e)
            raise HTTPException(status_code=400, detail="Invalid message data payload")

    if not bucket_name or not object_name:
        logger.error("Could not extract bucket and object from message: attributes=%s", message.attributes)
        # 400 Bad Request sends NACK/or DLQ routing in Pub/Sub
        raise HTTPException(status_code=400, detail="Missing bucket or object name in notification")

    logger.info("Processing document: gs://%s/%s", bucket_name, object_name)

    # 1. Download file content
    try:
        content_bytes = storage_service.download_file(bucket_name, object_name)
    except FileNotFoundError as fnf:
        logger.warning("File not found (may have been deleted): %s", fnf)
        # Return 200 so PubSub acknowledges and doesn't retry indefinitely for deleted objects
        return {"status": "skipped", "reason": "file not found"}
    except Exception as exc:
        logger.error("Failed downloading object gs://%s/%s: %s", bucket_name, object_name, exc)
        # Return 500 so Pub/Sub retries with backoff and moves to DLQ if persistent
        raise HTTPException(status_code=500, detail="Storage download failure")

    # 2. Simulated OCR extraction
    word_count, tags = simulated_ocr_process(content_bytes, object_name)
    processed_time = datetime.now(timezone.utc).isoformat()
    upload_time = upload_time or processed_time

    record = DocumentMetadata(
        filename=object_name,
        bucket=bucket_name,
        upload_time=upload_time,
        processed_time=processed_time,
        word_count=word_count,
        tags=tags,
        file_size_bytes=len(content_bytes),
        status="PROCESSED"
    )

    # 3. Stream to BigQuery using Storage Write API
    try:
        bq_writer_service.append_document_record(record.model_dump())
    except Exception as exc:
        logger.error("Failed writing metadata to BigQuery: %s", exc)
        raise HTTPException(status_code=500, detail="BigQuery write failure")

    logger.info("Successfully processed and recorded gs://%s/%s", bucket_name, object_name)
    return JSONResponse(status_code=200, content={"status": "success", "record": record.model_dump()})
