"""Admin-only endpoints: user list, per-project access grants, and gene-expression
cache management for preset datasets."""
import os
import threading
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.job import Job
from app.models.project_access import ProjectAccess
from app.models.user import User
from app.schemas.project_access import ProjectAccessGrant, ProjectAccessOut
from app.schemas.user import UserOut
from app.services.auth import require_admin
from app.services.expr_cache import (
    ASSUMED_ASSAYS,
    ASSUMED_SLOTS,
    build_expr_cache_bg,
    cache_base_for,
    cancel_project_job,
    evict,
    get_build_error,
    get_project_job,
    is_building,
    is_cached,
    list_cache_entries,
    list_project_jobs,
    start_project_cache_job,
)
from app.services.presets import PRESETS_DIR, list_project_names
from app.services.r_runner import run_r

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


# ── Gene expression cache management ──────────────────────────────────────────
# Lets an admin pre-warm the memory-mapped expression cache (the same one built
# lazily per-session in app.api.explore, see app.services.expr_cache) for any
# preset dataset, picking exactly which assay/slot to cache — without having to
# open the dataset in Explore first.
def _preset_rds_path(project: str, filename: str) -> str:
    if "/" in project or "\\" in project or "/" in filename or "\\" in filename:
        raise HTTPException(400, "Invalid path")
    rds_path = os.path.join(PRESETS_DIR, project, filename)
    if not os.path.exists(rds_path) or not filename.endswith(".rds"):
        raise HTTPException(404, "Preset file not found")
    return rds_path


@router.get("/cache/datasets")
async def list_cache_datasets(_admin: User = Depends(require_admin)):
    """Every preset .rds file on disk, with whatever (assay, slot) expression
    caches already exist for it — the admin cache-management dashboard's main list."""
    os.makedirs(PRESETS_DIR, exist_ok=True)
    datasets = []
    for project_dir in sorted(Path(PRESETS_DIR).iterdir()):
        if not project_dir.is_dir():
            continue
        for rds_file in sorted(project_dir.glob("*.rds"), key=lambda p: p.name):
            rds_path = str(rds_file)
            datasets.append({
                "project":     project_dir.name,
                "filename":    rds_file.name,
                "size_mb":     round(rds_file.stat().st_size / 1024 / 1024, 1),
                "caches":      list_cache_entries(rds_path),
            })
    return JSONResponse(datasets)


class InspectRequest(BaseModel):
    project:  str
    filename: str


@router.post("/cache/inspect")
async def inspect_dataset(req: InspectRequest, _admin: User = Depends(require_admin)):
    """Read a preset's assay/slot layout so the admin can pick what to cache.
    Loads the full RDS file in R, so this is slow for large datasets — call it
    on demand (e.g. when a dataset row is expanded), not on every page load."""
    rds_path = _preset_rds_path(req.project, req.filename)
    data = run_r("list_assay_slots.R", [rds_path], timeout=300)
    return JSONResponse(data)


class CacheBuildRequest(BaseModel):
    project:  str
    filename: str
    assay:    str
    slot:     str


@router.post("/cache/build")
async def admin_start_cache_build(req: CacheBuildRequest, _admin: User = Depends(require_admin)):
    rds_path = _preset_rds_path(req.project, req.filename)
    label = f"{req.assay}/{req.slot}"

    if is_cached(rds_path, req.assay, req.slot):
        return JSONResponse({"status": "exists", "message": f"Cache for {label} already exists — not running again."})
    if is_building(rds_path, req.assay, req.slot):
        return JSONResponse({"status": "building", "message": f"Cache for {label} is already being built."})

    cache_base = cache_base_for(rds_path)
    threading.Thread(
        target=build_expr_cache_bg,
        args=(rds_path, cache_base, req.assay, req.slot),
        daemon=True,
    ).start()
    return JSONResponse({"status": "started", "message": f"Started caching expression data for {label}…"})


@router.get("/cache/status")
async def admin_cache_status(
    project: str, filename: str, assay: str, slot: str,
    _admin: User = Depends(require_admin),
):
    rds_path = _preset_rds_path(project, filename)
    if is_building(rds_path, assay, slot):
        return JSONResponse({"status": "building"})
    if is_cached(rds_path, assay, slot):
        return JSONResponse({"status": "ready"})
    error = get_build_error(rds_path, assay, slot)
    if error:
        return JSONResponse({"status": "error", "error": error})
    return JSONResponse({"status": "not_cached"})


@router.delete("/cache")
async def admin_delete_cache(
    project: str, filename: str,
    assay: Optional[str] = None, slot: Optional[str] = None,
    _admin: User = Depends(require_admin),
):
    """Delete cached expression .bin/.json files for a preset dataset.
    With assay+slot, removes just that pair; without, removes every pair."""
    rds_path = _preset_rds_path(project, filename)
    cache_base = cache_base_for(rds_path)
    parent = Path(cache_base).parent
    prefix = Path(cache_base).name + "_"

    if assay and slot:
        paths = [parent / f"{prefix}{assay}_{slot}.bin", parent / f"{prefix}{assay}_{slot}.json"]
        evict(rds_path, assay, slot)
    else:
        paths = list(parent.glob(f"{prefix}*.bin")) + list(parent.glob(f"{prefix}*.json"))
        evict(rds_path)

    removed = 0
    for path in paths:
        if path.exists():
            path.unlink()
            removed += 1

    return JSONResponse({"status": "deleted", "removed": removed})


# ── Whole-project cache jobs ───────────────────────────────────────────────────
@router.get("/cache/options")
async def cache_build_options(_admin: User = Depends(require_admin)):
    """The fixed assay/slot choices offered for a whole-project cache run — see
    ASSUMED_ASSAYS/ASSUMED_SLOTS: deliberately not read off the data, so this
    doesn't require opening every file in a project first."""
    return JSONResponse({"assays": ASSUMED_ASSAYS, "slots": ASSUMED_SLOTS})


class ProjectCacheBuildRequest(BaseModel):
    project: str
    assays:  list[str]
    slots:   list[str]


@router.post("/cache/build-project")
async def admin_start_project_cache_build(req: ProjectCacheBuildRequest, _admin: User = Depends(require_admin)):
    if "/" in req.project or "\\" in req.project:
        raise HTTPException(400, "Invalid project name")
    project_dir = Path(PRESETS_DIR) / req.project
    if not project_dir.is_dir():
        raise HTTPException(404, "Project not found")

    bad_assays = [a for a in req.assays if a not in ASSUMED_ASSAYS]
    bad_slots  = [s for s in req.slots if s not in ASSUMED_SLOTS]
    if bad_assays or bad_slots:
        raise HTTPException(400, f"Unknown assay/slot: {bad_assays + bad_slots}")
    if not req.assays or not req.slots:
        raise HTTPException(400, "Select at least one assay and one data slot")

    rds_files = [(p.name, str(p)) for p in sorted(project_dir.glob("*.rds"), key=lambda p: p.name)]
    if not rds_files:
        raise HTTPException(400, "Project has no .rds files")

    job_id = start_project_cache_job(req.project, rds_files, req.assays, req.slots)
    return JSONResponse({
        "job_id": job_id,
        "total": len(rds_files) * len(req.assays) * len(req.slots),
    })


@router.get("/cache/build-project")
async def admin_list_project_cache_jobs(_admin: User = Depends(require_admin)):
    return JSONResponse(list_project_jobs())


@router.get("/cache/build-project/{job_id}")
async def admin_project_cache_status(job_id: str, _admin: User = Depends(require_admin)):
    job = get_project_job(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return JSONResponse(job)


@router.post("/cache/build-project/{job_id}/cancel")
async def admin_cancel_project_cache(job_id: str, _admin: User = Depends(require_admin)):
    if not cancel_project_job(job_id):
        raise HTTPException(400, "Job is not running")
    return JSONResponse({"status": "cancelled"})
