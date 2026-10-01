import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base


class PipelineSetting(Base):
    """Global visibility switch for one pipeline.

    A pipeline with no row here is visible by default, so the registry stays
    the source of truth and new pipelines don't need a row to show up.
    """

    __tablename__ = "pipeline_settings"

    pipeline_id: Mapped[str] = mapped_column(String, primary_key=True)
    is_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class PipelineAccess(Base):
    """Per-user override of the global switch, in either direction.

    allowed=True shows a globally hidden pipeline to this user;
    allowed=False hides a globally visible one from them.
    """

    __tablename__ = "pipeline_access"
    __table_args__ = (
        UniqueConstraint("user_id", "pipeline_id", name="uq_pipeline_access_user_pipeline"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, ForeignKey("users.id"))
    pipeline_id: Mapped[str] = mapped_column(String, index=True)
    allowed: Mapped[bool] = mapped_column(Boolean, default=True)
    granted_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
