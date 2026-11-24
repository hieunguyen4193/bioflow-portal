"""Browse data products registered in the RWTH DATA HUB metadata catalog
(https://datahub.tools.rpdm.rwth-aachen.de/api/docs).

DATA HUB only holds metadata. A product's `locations` say where the data
lives; when a location is an S3 URL (e.g. a Coscine RDS-S3 bucket on
global.datastorage.nrw) we parse it into endpoint / bucket / path so the
frontend can open it in the remote-storage browser, where the user supplies
the S3 read keys. No keys are ever read from or written to DATA HUB.

The DATA HUB base URL is fixed server-side (DATAHUB_BASE_URL), never taken
from the request, so this endpoint can't be used to make the server fetch
arbitrary URLs.
"""
import os
import re
from typing import Literal, Optional
from urllib.parse import unquote, urlparse

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.models.user import User
from app.services.auth import get_current_user

router = APIRouter(prefix="/explore/datahub", tags=["datahub"])

DATAHUB_BASE_URL = os.environ.get("DATAHUB_BASE_URL", "https://datahub.tools.rpdm.rwth-aachen.de").rstrip("/")

# Hosts whose path-style URLs are S3 objects: https://<host>/<bucket>/<key>
_S3_HOSTS = {
    h.strip().lower()
    for h in os.environ.get("DATAHUB_S3_HOSTS", "global.datastorage.nrw").split(",")
    if h.strip()
}
_DEFAULT_S3_ENDPOINT = "https://" + (sorted(_S3_HOSTS)[0] if _S3_HOSTS else "global.datastorage.nrw")

_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:~-]{0,199}$")
_GUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)


class ProductsRequest(BaseModel):
    project_id: str = Field(..., min_length=1, max_length=200)
    id_kind: Literal["public", "config"] = "public"
    token: Optional[str] = Field(None, max_length=500)


def _s3_target(url: str) -> Optional[dict]:
    """Turn a location URL into {endpoint, bucket, path, guessed} if it points at S3."""
    if not url:
        return None
    try:
        u = urlparse(url.strip())
    except ValueError:
        return None
    host = (u.hostname or "").lower()
    if u.scheme == "s3" and host:
        return {"endpoint": _DEFAULT_S3_ENDPOINT, "bucket": host,
                "path": unquote(u.path.lstrip("/")), "guessed": True}
    if u.scheme in ("https", "http") and (host in _S3_HOSTS or ".s3." in host or host.startswith("s3.")):
        parts = unquote(u.path).lstrip("/").split("/", 1)
        if not parts[0]:
            return None
        return {"endpoint": f"https://{host}" + (f":{u.port}" if u.port and u.port != 443 else ""),
                "bucket": parts[0], "path": parts[1] if len(parts) > 1 else "", "guessed": False}
    # Coscine web link to a resource: .../r/<resource-guid>... — the RDS-S3 bucket
    # name is the resource GUID, but the link doesn't say which S3 endpoint.
    if "coscine" in host:
        m = re.search(r"/r/(" + _GUID_RE.pattern + r")", u.path, re.I)
        if m:
            return {"endpoint": _DEFAULT_S3_ENDPOINT, "bucket": m.group(1).lower(),
                    "path": "", "guessed": True}
    return None


def _str(v) -> str:
    return v if isinstance(v, str) else ("" if v is None else str(v))


def _normalise(p: dict) -> dict:
    locs = []
    for loc in p.get("locations") or []:
        if not isinstance(loc, dict):
            continue
        url = _str(loc.get("url"))
        locs.append({
            "type": _str(loc.get("type")), "label": _str(loc.get("label")),
            "url": url, "access": _str(loc.get("access")),
            "s3": _s3_target(url),
        })
    return {
        "id": _str(p.get("id")),
        "registry_id": _str(p.get("registryId")),
        "name": _str(p.get("name")) or _str(p.get("id")),
        "description": _str(p.get("description")),
        "domain": _str(p.get("domain")),
        "modality": _str(p.get("modality")),
        "format": _str(p.get("format")),
        "status": _str(p.get("status")),
        "lifecycle": _str(p.get("lifecycle")),
        "access": _str(p.get("access")),
        "access_procedure": _str(p.get("accessProcedure")),
        "license": _str(p.get("license")),
        "version": _str(p.get("version")),
        "data_steward": _str(p.get("dataSteward")),
        "updated": _str(p.get("updated")),
        "size_gb": p.get("sizeGb") if isinstance(p.get("sizeGb"), (int, float)) else None,
        "records": p.get("records") if isinstance(p.get("records"), int) else None,
        "keywords": [k for k in (p.get("keywords") or []) if isinstance(k, str)],
        "imported": bool(p.get("imported")),
        "locations": locs,
    }


@router.post("/products")
async def list_products(req: ProductsRequest, current_user: User = Depends(get_current_user)):
    pid = req.project_id.strip()
    if not _ID_RE.match(pid):
        raise HTTPException(400, "Invalid project ID")
    kind = "public" if req.id_kind == "public" else "configs"
    url = f"{DATAHUB_BASE_URL}/api/{kind}/{pid}/data-products"
    headers = {"Accept": "application/json", "User-Agent": "BioInfoLab"}
    if req.token and req.token.strip():
        headers["X-Write-Token"] = req.token.strip()
    try:
        async with httpx.AsyncClient(timeout=30, follow_redirects=False) as client:
            r = await client.get(url, headers=headers)
    except httpx.HTTPError as exc:
        raise HTTPException(502, f"Could not reach DATA HUB: {type(exc).__name__}")
    if r.status_code == 404:
        raise HTTPException(404, "DATA HUB project not found. Check the ID and whether it is a public ID or a config ID.")
    if r.status_code in (401, 403):
        raise HTTPException(403, "DATA HUB refused access. Check the token.")
    if r.status_code != 200:
        raise HTTPException(502, f"DATA HUB returned HTTP {r.status_code}")
    try:
        body = r.json()
    except ValueError:
        raise HTTPException(502, "DATA HUB returned an unexpected response")
    raw = body.get("dataProducts") if isinstance(body, dict) else body
    if not isinstance(raw, list):
        raise HTTPException(502, "DATA HUB returned an unexpected response")
    products = [_normalise(p) for p in raw if isinstance(p, dict)]
    products.sort(key=lambda p: p["name"].lower())
    return {"project_id": pid, "id_kind": req.id_kind, "base_url": DATAHUB_BASE_URL,
            "count": len(products), "products": products}
