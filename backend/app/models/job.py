import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base


class Job(Base):
    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, ForeignKey("users.id"))
    pipeline: Mapped[str] = mapped_column(String)           # e.g. "seurat_from_10x"
    status: Mapped[str] = mapped_column(String, default="queued")  # queued|running|done|failed
    params: Mapped[dict] = mapped_column(JSON, default=dict)
    input_files: Mapped[list] = mapped_column(JSON, default=list)  # relative paths under UPLOAD_DIR
    output_dir: Mapped[str | None] = mapped_column(String, nullable=True)
    celery_task_id: Mapped[str | None] = mapped_column(String, nullable=True)
    slurm_job_id: Mapped[str | None] = mapped_column(String, nullable=True)
    log: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user: Mapped["User"] = relationship("User", back_populates="jobs")  # noqa: F821
