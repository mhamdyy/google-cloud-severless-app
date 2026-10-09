import logging
from typing import Dict, Any, List
from google.cloud import storage
from google.cloud.bigquery_storage_v1 import BigQueryWriteClient, types
from google.protobuf import descriptor_pb2

from app.config import settings

logger = logging.getLogger(__name__)

class StorageService:
    def __init__(self, client: storage.Client = None):
        self._client = client

    @property
    def client(self) -> storage.Client:
        if self._client is None:
            self._client = storage.Client(project=settings.PROJECT_ID)
        return self._client

    def download_file(self, bucket_name: str, object_name: str) -> bytes:
        bucket = self.client.bucket(bucket_name)
        blob = bucket.blob(object_name)
        if not blob.exists():
            raise FileNotFoundError(f"Blob {object_name} not found in bucket {bucket_name}")
        return blob.download_as_bytes()


class BigQueryWriterService:
    """
    Writes records into BigQuery using the BigQuery Storage Write API default stream.
    Supports local mock mode for development and automated testing.
    """
    def __init__(self, write_client: BigQueryWriteClient = None):
        self._write_client = write_client

    @property
    def write_client(self) -> BigQueryWriteClient:
        if self._write_client is None:
            self._write_client = BigQueryWriteClient()
        return self._write_client

    def append_document_record(self, record_dict: Dict[str, Any]):
        if settings.ENVIRONMENT == "test" or settings.PROJECT_ID == "local-project":
            logger.info("Local/Test environment detected. Mocking BigQuery Storage Write API append: %s", record_dict)
            return

        # Target default stream path: projects/{project}/datasets/{dataset}/tables/{table}/_default
        parent = self.write_client.table_path(
            settings.PROJECT_ID,
            settings.BQ_DATASET,
            settings.BQ_TABLE
        )
        write_stream = f"{parent}/_default"

        # Lazy import of compiled protobuf message
        from app.proto import document_metadata_pb2

        proto_record = document_metadata_pb2.DocumentMetadataRecord(
            filename=record_dict["filename"],
            bucket=record_dict["bucket"],
            upload_time=record_dict["upload_time"],
            processed_time=record_dict["processed_time"],
            word_count=record_dict["word_count"],
            tags=record_dict["tags"],
            file_size_bytes=record_dict["file_size_bytes"],
            status=record_dict["status"]
        )

        proto_rows = types.ProtoRows(serialized_rows=[proto_record.SerializeToString()])

        proto_schema = types.ProtoSchema()
        descriptor_pb2.DescriptorProto.FromString(
            document_metadata_pb2.DocumentMetadataRecord.DESCRIPTOR.serialized_pb
        )
        proto_schema.proto_descriptor.CopyFrom(
            descriptor_pb2.DescriptorProto.FromString(
                document_metadata_pb2.DocumentMetadataRecord.DESCRIPTOR.serialized_pb
            )
        )

        request = types.AppendRowsRequest(
            write_stream=write_stream,
            proto_rows=types.AppendRowsRequest.ProtoData(
                writer_schema=proto_schema,
                rows=proto_rows
            )
        )

        append_stream = self.write_client.append_rows(requests=iter([request]))
        for response in append_stream:
            if response.error.code != 0:
                logger.error("BigQuery Storage Write API error: %s", response.error.message)
                raise RuntimeError(f"Storage Write API Error: {response.error.message}")
            logger.info("Successfully appended row to BigQuery default stream.")
