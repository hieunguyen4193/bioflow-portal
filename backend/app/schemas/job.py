from datetime import datetime
from pydantic import BaseModel


class JobCreate(BaseModel):
    pipeline: str
    params: dict = {}


class JobOut(BaseModel):
    id: str
    pipeline: str
    status: str
    params: dict
    input_files: list
    output_dir: str | None
    log: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
