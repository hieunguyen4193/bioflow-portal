"""Visibility rules for pipelines in the "Run Pipeline" section.

A pipeline is visible to a user when:
  * the user is an admin (admins always see everything), or
  * an explicit per-user override exists — it wins outright, or
  * otherwise, the pipeline's global switch is on (the default).
"""
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.pipeline_access import PipelineAccess, PipelineSetting
from app.models.user import User


async def global_switches(db: AsyncSession) -> dict[str, bool]:
    """pipeline_id -> is_enabled, for pipelines that have a stored setting."""
    result = await db.execute(select(PipelineSetting.pipeline_id, PipelineSetting.is_enabled))
    return {row[0]: row[1] for row in result.all()}


async def user_overrides(db: AsyncSession, user_id: str) -> dict[str, bool]:
    """pipeline_id -> allowed, for this user's explicit overrides."""
    result = await db.execute(
        select(PipelineAccess.pipeline_id, PipelineAccess.allowed).where(
            PipelineAccess.user_id == user_id
        )
    )
    return {row[0]: row[1] for row in result.all()}


async def visible_pipeline_ids(db: AsyncSession, user: User, all_ids: list[str]) -> list[str]:
    if user.is_admin:
        return list(all_ids)
    enabled = await global_switches(db)
    overrides = await user_overrides(db, user.id)
    return [
        pid for pid in all_ids
        if overrides.get(pid, enabled.get(pid, True))
    ]


async def user_can_run_pipeline(db: AsyncSession, user: User, pipeline_id: str) -> bool:
    if user.is_admin:
        return True
    result = await db.execute(
        select(PipelineAccess.allowed).where(
            PipelineAccess.user_id == user.id,
            PipelineAccess.pipeline_id == pipeline_id,
        )
    )
    override = result.scalar_one_or_none()
    if override is not None:
        return override
    result = await db.execute(
        select(PipelineSetting.is_enabled).where(PipelineSetting.pipeline_id == pipeline_id)
    )
    setting = result.scalar_one_or_none()
    return True if setting is None else setting
