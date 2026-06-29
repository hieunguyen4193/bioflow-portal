from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str
    CELERY_BROKER_URL: str
    CELERY_RESULT_BACKEND: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080

    UPLOAD_DIR: str = "/data/uploads"
    RESULTS_DIR: str = "/data/results"
    NEXTFLOW_BIN: str = "nextflow"
    NEXTFLOW_PIPELINES_DIR: str = "/nextflow/pipelines"

    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    EMAILS_FROM: str = "noreply@bioflow.local"

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
