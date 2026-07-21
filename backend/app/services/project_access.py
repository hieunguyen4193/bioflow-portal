from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.project_access import ProjectAccess
from app.models.user import User


async def user_has_project_access(db: AsyncSession, user: User, project_name: str) -> bool:
    if user.is_admin:
        return True
    result = await db.execute(
        select(ProjectAccess).where(
            ProjectAccess.user_id == user.id,
            ProjectAccess.project_name == project_name,
        )
    )
    return result.scalar_one_or_none() is not None


async def accessible_project_names(db: AsyncSession, user: User, all_names: list[str]) -> list[str]:
    if user.is_admin:
        return all_names
    result = await db.execute(
        select(ProjectAccess.project_name).where(ProjectAccess.user_id == user.id)
    )
    granted = {row[0] for row in result.all()}
    return [name for name in all_names if name in granted]
