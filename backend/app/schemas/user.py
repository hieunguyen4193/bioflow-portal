from typing import Optional
from pydantic import BaseModel, EmailStr, Field


class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_.-]+$")
    email: Optional[EmailStr] = None
    full_name: str
    password: str


class UserOut(BaseModel):
    id: str
    username: str
    email: Optional[str] = None
    full_name: str
    is_active: bool
    is_admin: bool

    model_config = {"from_attributes": True}


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
