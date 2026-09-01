"""Chunked file upload endpoint (compatible with tus-js-client and plain multipart)."""
import os
import uuid
import aiofiles
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from app.core.config import settings
from app.models.user import User
from app.services.auth import get_current_user

router = APIRouter(prefix="/files", tags=["files"])

CHUNK_SIZE = 1024 * 1024  # 1 MB


@router.post("/upload")
async def upload_files(
    files: list[UploadFile] = File(...),
    current_user: User = Depends(get_current_user),
):
    """Accept one or more files, store under UPLOAD_DIR/<user_id>/<batch_id>/."""
    batch_id = str(uuid.uuid4())
    dest_dir = os.path.join(settings.UPLOAD_DIR, current_user.id, batch_id)
    os.makedirs(dest_dir, exist_ok=True)

    saved = []
    seen_rel_paths: set[str] = set()
    for upload in files:
        raw_name = (upload.filename or "file").replace("\\", "/")
        # Folder uploads carry a relative path (e.g. "SampleA/barcodes.tsv.gz") —
        # keep that structure so identically-named files from different samples
        # don't collide; strip any ".."/empty segments to stay inside dest_dir.
        parts = [p for p in raw_name.split("/") if p not in ("", ".", "..")]
        if not parts:
            raise HTTPException(400, f"Invalid filename: {upload.filename!r}")
        rel_path = os.path.join(*parts)
        if rel_path in seen_rel_paths:
            raise HTTPException(400, f"Duplicate file in upload: {rel_path}")
        seen_rel_paths.add(rel_path)

        dest_path = os.path.join(dest_dir, rel_path)
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        async with aiofiles.open(dest_path, "wb") as f:
            while chunk := await upload.read(CHUNK_SIZE):
                await f.write(chunk)
        saved.append({"filename": rel_path, "path": os.path.relpath(dest_path, settings.UPLOAD_DIR)})

    return {"batch_id": batch_id, "files": saved}
