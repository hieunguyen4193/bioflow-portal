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
    for upload in files:
        filename = os.path.basename(upload.filename or "file")
        dest_path = os.path.join(dest_dir, filename)
        async with aiofiles.open(dest_path, "wb") as f:
            while chunk := await upload.read(CHUNK_SIZE):
                await f.write(chunk)
        saved.append({"filename": filename, "path": os.path.relpath(dest_path, settings.UPLOAD_DIR)})

    return {"batch_id": batch_id, "files": saved}
