"""Browse and load Seurat objects from S3-compatible remote storage (e.g. a
Coscine RDS-S3 resource at https://global.datastorage.nrw).

Credentials are sent by the browser with each request and only live in memory
for the duration of that request / download thread. They are never written to
disk, the database or the logs.

A loaded object is downloaded once into EXPLORE_DIR/remote/<hash>/<file>.rds,
keyed by endpoint + bucket + key. It is re-downloaded only when the remote
ETag or size changes, so the per-file result caches (DGE, sub-cluster,
pathway) keep working across loads.
"""
import hashlib
import json
import os
import threading
import uuid
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlparse

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError, EndpointConnectionError
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.explore import open_rds_session, _require_task_owner
from app.models.user import User
from app.services.auth import get_current_user
from app.services.presets import EXPLORE_DIR

router = APIRouter(prefix="/explore/remote", tags=["remote-storage"])

REMOTE_DIR = os.path.join(EXPLORE_DIR, "remote")

# Optional allowlist of endpoint hostnames, comma-separated. Empty = any https host.
_ALLOWED_HOSTS = {h.strip().lower() for h in os.environ.get("REMOTE_S3_ALLOWED_HOSTS", "").split(",") if h.strip()}

_MAX_LIST = 5000

_load_tasks: dict[str, dict] = {}


class _Cancelled(Exception):
    pass


class RemoteCreds(BaseModel):
    endpoint: str = Field(..., max_length=500)
    bucket: str = Field(..., min_length=1, max_length=255)
    access_key: str = Field(..., min_length=1, max_length=500)
    secret_key: str = Field(..., min_length=1, max_length=500)


class ListRequest(RemoteCreds):
    prefix: str = ""


class LoadRequest(RemoteCreds):
    key: str = Field(..., min_length=1, max_length=1024)


def _normalise_endpoint(endpoint: str) -> str:
    endpoint = endpoint.strip().rstrip("/")
    if "://" not in endpoint:
        endpoint = "https://" + endpoint
    u = urlparse(endpoint)
    if u.scheme != "https" or not u.hostname:
        raise HTTPException(400, "Endpoint must be an https:// URL")
    if u.path not in ("", "/") or u.query or u.username:
        raise HTTPException(400, "Endpoint must be a bare host URL, like https://global.datastorage.nrw")
    if _ALLOWED_HOSTS and u.hostname.lower() not in _ALLOWED_HOSTS:
        raise HTTPException(400, f"Endpoint host {u.hostname} is not allowed on this server")
    return f"https://{u.hostname}" + (f":{u.port}" if u.port else "")


def _client(c: RemoteCreds):
    return boto3.client(
        "s3",
        endpoint_url=_normalise_endpoint(c.endpoint),
        aws_access_key_id=c.access_key.strip(),
        aws_secret_access_key=c.secret_key.strip(),
        region_name="us-east-1",
        config=Config(
            s3={"addressing_style": "path"},
            signature_version="s3v4",
            connect_timeout=15,
            read_timeout=120,
            retries={"max_attempts": 3},
        ),
    )


def _s3_error(exc: Exception) -> HTTPException:
    if isinstance(exc, ClientError):
        code = exc.response.get("Error", {}).get("Code", "")
        if code in ("InvalidAccessKeyId", "SignatureDoesNotMatch", "AccessDenied", "403"):
            return HTTPException(403, "Access denied: check the access key and secret key")
        if code in ("NoSuchBucket", "404"):
            return HTTPException(404, "Bucket or file not found")
        return HTTPException(502, f"Storage error: {code or exc}")
    if isinstance(exc, EndpointConnectionError):
        return HTTPException(502, "Could not connect to the endpoint")
    return HTTPException(502, f"Storage error: {exc}")


@router.post("/list")
def list_remote(req: ListRequest, current_user: User = Depends(get_current_user)):
    """One folder level of the bucket: sub-folders and files under `prefix`."""
    prefix = req.prefix.lstrip("/")
    if prefix and not prefix.endswith("/"):
        prefix += "/"
    s3 = _client(req)
    folders: list[dict] = []
    files: list[dict] = []
    truncated = False
    try:
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=req.bucket, Prefix=prefix, Delimiter="/"):
            for p in page.get("CommonPrefixes", []):
                folders.append({"prefix": p["Prefix"], "name": p["Prefix"][len(prefix):].rstrip("/")})
            for o in page.get("Contents", []):
                if o["Key"] == prefix:      # the folder placeholder object itself
                    continue
                files.append({
                    "key": o["Key"],
                    "name": o["Key"][len(prefix):],
                    "size": o["Size"],
                    "last_modified": o["LastModified"].isoformat(),
                })
            if len(folders) + len(files) >= _MAX_LIST:
                truncated = True
                break
    except (ClientError, BotoCoreError) as exc:
        raise _s3_error(exc)
    folders.sort(key=lambda f: f["name"].lower())
    files.sort(key=lambda f: f["name"].lower())
    return {"prefix": prefix, "folders": folders, "files": files, "truncated": truncated}


def _local_path_for(endpoint: str, bucket: str, key: str) -> str:
    h = hashlib.sha256(f"{endpoint}\n{bucket}\n{key}".encode()).hexdigest()[:24]
    name = os.path.basename(key) or "object.rds"
    name = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in name)
    return os.path.join(REMOTE_DIR, h, name)


def _run_load(task_id: str, req: LoadRequest, owner_id: str) -> None:
    task = _load_tasks[task_id]
    try:
        endpoint = _normalise_endpoint(req.endpoint)
        s3 = _client(req)
        try:
            head = s3.head_object(Bucket=req.bucket, Key=req.key)
        except (ClientError, BotoCoreError) as exc:
            raise _s3_error(exc)
        size = int(head.get("ContentLength") or 0)
        etag = (head.get("ETag") or "").strip('"')
        task["bytes_total"] = size

        local = _local_path_for(endpoint, req.bucket, req.key)
        meta_path = local + ".remote.json"
        cached = False
        if os.path.isfile(local) and os.path.isfile(meta_path):
            try:
                with open(meta_path) as f:
                    m = json.load(f)
                cached = m.get("etag") == etag and m.get("size") == size and os.path.getsize(local) == size
            except (OSError, ValueError):
                cached = False

        if cached:
            task["bytes_done"] = size
            task["from_cache"] = True
        else:
            os.makedirs(os.path.dirname(local), exist_ok=True)
            part = local + ".part"

            def _progress(n: int) -> None:
                if task.get("cancel"):
                    raise _Cancelled()
                task["bytes_done"] += n

            try:
                s3.download_file(req.bucket, req.key, part, Callback=_progress)
            except _Cancelled:
                raise
            except (ClientError, BotoCoreError) as exc:
                raise _s3_error(exc)
            finally:
                if task.get("cancel") and os.path.exists(part):
                    os.remove(part)
            os.replace(part, local)
            with open(meta_path, "w") as f:
                json.dump({
                    "endpoint": endpoint, "bucket": req.bucket, "key": req.key,
                    "etag": etag, "size": size,
                    "downloaded_at": datetime.now(timezone.utc).isoformat(),
                }, f)

        if task.get("cancel"):
            raise _Cancelled()
        task["phase"] = "reading"
        data = open_rds_session(local, f"{req.bucket}/{req.key}", owner_id)
        data["remote_source"] = {"endpoint": endpoint, "bucket": req.bucket, "key": req.key}
        task["result"] = data
        task["phase"] = "done"
        task["status"] = "done"
    except _Cancelled:
        task["status"] = "cancelled"
        task["error"] = "Cancelled"
    except HTTPException as exc:
        task["status"] = "error"
        task["error"] = exc.detail
    except Exception as exc:  # noqa: BLE001 — surface anything to the UI
        task["status"] = "error"
        task["error"] = str(exc)


@router.post("/load/start")
def start_remote_load(req: LoadRequest, current_user: User = Depends(get_current_user)):
    if not req.key.lower().endswith(".rds"):
        raise HTTPException(400, "Only .rds files can be loaded")
    _normalise_endpoint(req.endpoint)
    task_id = str(uuid.uuid4())
    _load_tasks[task_id] = {
        "owner": current_user.id, "status": "running", "phase": "downloading",
        "bytes_done": 0, "bytes_total": None, "from_cache": False,
        "key": req.key, "result": None, "error": None, "cancel": False,
    }
    threading.Thread(target=_run_load, args=(task_id, req, current_user.id), daemon=True).start()
    return {"task_id": task_id}


@router.get("/load/{task_id}")
def get_remote_load(task_id: str, current_user: User = Depends(get_current_user)):
    task = _load_tasks.get(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")
    _require_task_owner(task, current_user)
    out = {k: task[k] for k in ("status", "phase", "bytes_done", "bytes_total", "from_cache", "key", "error")}
    if task["status"] == "done":
        out["result"] = task["result"]
        _load_tasks.pop(task_id, None)   # result handed over; free the memory
    elif task["status"] in ("error", "cancelled"):
        _load_tasks.pop(task_id, None)
    return out


@router.post("/load/{task_id}/cancel")
def cancel_remote_load(task_id: str, current_user: User = Depends(get_current_user)):
    task = _load_tasks.get(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")
    _require_task_owner(task, current_user)
    task["cancel"] = True
    return {"status": "cancelling"}
