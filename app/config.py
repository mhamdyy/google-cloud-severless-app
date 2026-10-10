import os

class Settings:
    PROJECT_ID: str = os.getenv("PROJECT_ID", "local-project")
    BQ_DATASET: str = os.getenv("BQ_DATASET", "document_processing")
    BQ_TABLE: str = os.getenv("BQ_TABLE", "document_metadata")
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "production")

settings = Settings()
