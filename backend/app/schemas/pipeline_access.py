from pydantic import BaseModel


class PipelineOverrideOut(BaseModel):
    id: str
    user_id: str
    username: str
    full_name: str
    allowed: bool


class PipelineVisibilityOut(BaseModel):
    id: str
    name: str
    description: str | None = None
    is_enabled: bool
    overrides: list[PipelineOverrideOut]


class PipelineToggle(BaseModel):
    is_enabled: bool


class PipelineOverrideSet(BaseModel):
    username: str
    pipeline_id: str
    allowed: bool
