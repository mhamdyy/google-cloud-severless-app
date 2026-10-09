from pydantic import BaseModel
from typing import List, Optional, Dict, Any

class PubSubMessage(BaseModel):
    data: Optional[str] = None
    attributes: Optional[Dict[str, Any]] = None
    messageId: Optional[str] = None
    publishTime: Optional[str] = None

class PubSubPushPayload(BaseModel):
    message: PubSubMessage
    subscription: Optional[str] = None

class DocumentMetadata(BaseModel):
    filename: str
    bucket: str
    upload_time: str
    processed_time: str
    word_count: int
    tags: List[str]
    file_size_bytes: int
    status: str
