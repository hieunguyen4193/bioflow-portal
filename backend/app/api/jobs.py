import os
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from app.core.database import get_db
from app.core.config import settings
from app.core.security import decode_token
from app.models.job import Job
from app.models.user import User
from app.schemas.job import JobCreate, JobOut
from app.services.auth import get_current_user

router = APIRouter(prefix="/jobs", tags=["jobs"])


@router.post("/", response_model=JobOut, status_code=201)
async def submit_job(
    body: JobCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.workers.runner import launch

    batch_id = body.params.pop("batch_id", None)
    if not batch_id:
        raise HTTPException(400, "batch_id required in params")

    input_dir = os.path.join(settings.UPLOAD_DIR, current_user.id, batch_id)
    if not os.path.isdir(input_dir):
        raise HTTPException(400, "Unknown batch_id")

    input_files = [
        os.path.relpath(os.path.join(input_dir, f), settings.UPLOAD_DIR)
        for f in os.listdir(input_dir)
    ]

    job = Job(
        user_id=current_user.id,
        pipeline=body.pipeline,
        params=body.params,
        input_files=input_files,
        status="queued",
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    launch(job.id)
    return job


@router.get("/", response_model=list[JobOut])
async def list_jobs(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Job).where(Job.user_id == current_user.id).order_by(Job.created_at.desc())
    )
    return result.scalars().all()


@router.get("/{job_id}", response_model=JobOut)
async def get_job(
    job_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(Job).where(Job.id == job_id, Job.user_id == current_user.id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(404, "Job not found")
    return job


@router.get("/{job_id}/files")
async def list_output_files(
    job_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(Job).where(Job.id == job_id, Job.user_id == current_user.id))
    job = result.scalar_one_or_none()
    if not job or not job.output_dir:
        raise HTTPException(404, "No outputs yet")

    output_path = os.path.join(settings.RESULTS_DIR, job.output_dir)
    if not os.path.isdir(output_path):
        return []

    files = []
    for root, dirs, filenames in os.walk(output_path):
        # skip nextflow work/cache dirs
        dirs[:] = [d for d in dirs if d not in ("work", ".nextflow")]
        for fname in filenames:
            if fname.startswith("."):
                continue
            full = os.path.join(root, fname)
            rel = os.path.relpath(full, output_path)
            files.append({"name": rel, "size": os.path.getsize(full)})
    return files


@router.get("/{job_id}/files/paths")
async def list_output_file_paths(
    job_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return absolute server-side paths for all output files as plain text (one per line)."""
    from fastapi.responses import PlainTextResponse
    result = await db.execute(select(Job).where(Job.id == job_id, Job.user_id == current_user.id))
    job = result.scalar_one_or_none()
    if not job or not job.output_dir:
        raise HTTPException(404, "No outputs yet")

    output_path = os.path.join(settings.RESULTS_DIR, job.output_dir)
    if not os.path.isdir(output_path):
        return PlainTextResponse("")

    paths = []
    for root, dirs, filenames in os.walk(output_path):
        dirs[:] = [d for d in dirs if d not in ("work", ".nextflow")]
        for fname in filenames:
            if fname.startswith("."):
                continue
            paths.append(os.path.join(root, fname))

    paths.sort()
    return PlainTextResponse("\n".join(paths))


@router.post("/{job_id}/stop")
async def stop_job(
    job_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.workers.runner import stop_job as _stop
    result = await db.execute(select(Job).where(Job.id == job_id, Job.user_id == current_user.id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(404, "Job not found")
    if job.status != "running":
        raise HTTPException(400, f"Job is not running (status: {job.status})")
    _stop(job_id)
    return {"status": "cancelled"}


@router.post("/{job_id}/pause")
async def pause_job(
    job_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.workers.runner import pause_job as _pause
    result = await db.execute(select(Job).where(Job.id == job_id, Job.user_id == current_user.id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(404, "Job not found")
    if job.status != "running":
        raise HTTPException(400, f"Job is not running (status: {job.status})")
    _pause(job_id)
    return {"status": "paused"}


@router.post("/{job_id}/resume")
async def resume_job(
    job_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.workers.runner import resume_job as _resume
    result = await db.execute(select(Job).where(Job.id == job_id, Job.user_id == current_user.id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(404, "Job not found")
    if job.status != "paused":
        raise HTTPException(400, f"Job is not paused (status: {job.status})")
    ok = _resume(job_id)
    if not ok:
        raise HTTPException(500, "Failed to resume job")
    return {"status": "running"}


@router.get("/{job_id}/download/{file_path:path}")
async def download_file(
    job_id: str,
    file_path: str,
    token: str = Query(...),
    db: AsyncSession = Depends(get_db),
):
    # authenticate via query param token (needed for direct browser downloads)
    email = decode_token(token)
    if not email:
        raise HTTPException(401, "Invalid token")
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(401, "User not found")

    result = await db.execute(select(Job).where(Job.id == job_id, Job.user_id == user.id))
    job = result.scalar_one_or_none()
    if not job or not job.output_dir:
        raise HTTPException(404, "Job not found")

    allowed_root = os.path.realpath(os.path.join(settings.RESULTS_DIR, job.output_dir))
    full_path = os.path.realpath(os.path.join(allowed_root, file_path))
    if not full_path.startswith(allowed_root):
        raise HTTPException(403, "Access denied")
    if not os.path.isfile(full_path):
        raise HTTPException(404, "File not found")

    return FileResponse(full_path, filename=os.path.basename(full_path))


@router.delete("/", status_code=204)
async def clear_jobs(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete all jobs belonging to the current user."""
    await db.execute(delete(Job).where(Job.user_id == current_user.id))
    await db.commit()
