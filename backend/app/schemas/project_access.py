from pydantic import BaseModel


class ProjectAccessOut(BaseModel):
    id: str
    user_id: str
    username: str
    project_name: str

    model_config = {"from_attributes": True}


class ProjectAccessGrant(BaseModel):
    username: str
    project_name: str
