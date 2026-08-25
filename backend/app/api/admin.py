"""Admin-only endpoints: user list and per-project access grants."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.job import Job
from app.models.project_access import ProjectAccess
from app.models.user import User
from app.schemas.project_access import ProjectAccessGrant, ProjectAccessOut
from app.schemas.user import UserOut
from app.services.auth import require_admin
from app.services.presets import list_project_names

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/users", response_model=list[UserOut])
async def list_users(db: AsyncSession = Depends(get_db), _admin: User = Depends(require_admin)):
    result = await db.execute(select(User).order_by(User.username))
    return result.scalars().all()


@router.delete("/users/{user_id}", status_code=204)
async def delete_user(
    user_id: str,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_admin),
):
    if user_id == admin.id:
        raise HTTPException(400, "Cannot delete your own account")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(404, "User not found")
    if user.is_admin:
        raise HTTPException(400, "Cannot delete an admin account")

    job_count = await db.scalar(select(func.count()).select_from(Job).where(Job.user_id == user_id))
    if job_count:
        raise HTTPException(400, f"User has {job_count} job(s) and cannot be deleted")

    await db.execute(delete(ProjectAccess).where(ProjectAccess.user_id == user_id))
    await db.delete(user)
    await db.commit()


@router.get("/projects", response_model=list[str])
async def list_projects(_admin: User = Depends(require_admin)):
    return list_project_names()


@router.get("/project-access", response_model=list[ProjectAccessOut])
async def list_project_access(db: AsyncSession = Depends(get_db), _admin: User = Depends(require_admin)):
    result = await db.execute(
        select(ProjectAccess, User.username)
        .join(User, User.id == ProjectAccess.user_id)
        .order_by(ProjectAccess.project_name, User.username)
    )
    return [
        ProjectAccessOut(id=grant.id, user_id=grant.user_id, username=username, project_name=grant.project_name)
        for grant, username in result.all()
    ]


@router.post("/project-access", response_model=ProjectAccessOut, status_code=201)
async def grant_project_access(
    body: ProjectAccessGrant,
    db: AsyncSession = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    if body.project_name not in list_project_names():
        raise HTTPException(404, "Project not found")
    result = await db.execute(select(User).where(User.username == body.username))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(404, "User not found")

    existing = await db.execute(
        select(ProjectAccess).where(
            ProjectAccess.user_id == user.id,
            ProjectAccess.project_name == body.project_name,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(400, "User already has access to this project")

    grant = ProjectAccess(user_id=user.id, project_name=body.project_name)
    db.add(grant)
    await db.commit()
    await db.refresh(grant)
    return ProjectAccessOut(id=grant.id, user_id=grant.user_id, username=user.username, project_name=grant.project_name)


@router.delete("/project-access/{grant_id}", status_code=204)
async def revoke_project_access(
    grant_id: str,
    db: AsyncSession = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    result = await db.execute(select(ProjectAccess).where(ProjectAccess.id == grant_id))
    grant = result.scalar_one_or_none()
    if not grant:
        raise HTTPException(404, "Grant not found")
    await db.delete(grant)
    await db.commit()
