"""Interactive exploration API — upload a Seurat RDS and explore it."""
import json
import os
import subprocess
import uuid
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel

router = APIRouter(prefix="/explore", tags=["explore"])

_sessions: dict[str, str] = {}   # session_id → absolute rds path (host path)

EXPLORE_DIR  = "/Users/hieunguyen/src/bioflow-portal/data/explore"
PRESETS_DIR  = os.path.join(EXPLORE_DIR, "presets")
R_SCRIPTS   = "/Users/hieunguyen/src/bioflow-portal/backend/app/r_scripts"
DOCKER_IMAGE = os.environ.get("PIPELINE_IMAGE", "tronghieunguyen/single_cell_pipeline")


def _run_r(script_name: str, args: list[str], timeout: int = 300) -> dict | list:
    script_path = os.path.join(R_SCRIPTS, script_name)
    cmd = [
        "docker", "run", "--rm",
        "-v", f"{EXPLORE_DIR}:{EXPLORE_DIR}",
        "-v", f"{R_SCRIPTS}:{R_SCRIPTS}",
        DOCKER_IMAGE,
        "Rscript", "--vanilla", script_path, *args,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        raise HTTPException(500, f"R error:\n{result.stderr[-3000:]}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise HTTPException(500, f"R parse error: {exc}\nstdout[:500]: {result.stdout[:500]}")


# ── Presets ─────────────────────────────────────────────────────────────────
@router.get("/presets")
async def list_presets():
    os.makedirs(PRESETS_DIR, exist_ok=True)
    projects = []
    for project_dir in sorted(Path(PRESETS_DIR).iterdir()):
        if not project_dir.is_dir():
            continue
        files = sorted(project_dir.glob("*.rds"), key=lambda p: p.name)
        if not files:
            continue
        projects.append({
            "project": project_dir.name,
            "files": [
                {"name": p.stem, "filename": p.name, "size_mb": round(p.stat().st_size / 1024 / 1024, 1)}
                for p in files
            ],
        })
    return projects


class PresetLoadRequest(BaseModel):
    project: str
    filename: str


@router.post("/presets/load")
async def load_preset(req: PresetLoadRequest):
    if "/" in req.project or "\\" in req.project or "/" in req.filename or "\\" in req.filename:
        raise HTTPException(400, "Invalid path")
    rds_path = os.path.join(PRESETS_DIR, req.project, req.filename)
    if not os.path.exists(rds_path) or not req.filename.endswith(".rds"):
        raise HTTPException(400, "Preset file not found")
    session_id = str(uuid.uuid4())
    _sessions[session_id] = rds_path
    data = _run_r("extract_seurat.R", [rds_path], timeout=180)
    data["session_id"] = session_id
    return JSONResponse(data)


# ── Upload ──────────────────────────────────────────────────────────────────
@router.post("/upload")
async def upload_rds(file: UploadFile = File(...)):
    if not (file.filename or "").endswith(".rds"):
        raise HTTPException(400, "Only .rds files are supported")

    session_id = str(uuid.uuid4())
    rds_path   = os.path.join(EXPLORE_DIR, f"{session_id}.rds")
    os.makedirs(EXPLORE_DIR, exist_ok=True)

    content = await file.read()
    with open(rds_path, "wb") as f:
        f.write(content)

    _sessions[session_id] = rds_path

    data = _run_r("extract_seurat.R", [rds_path], timeout=180)
    data["session_id"] = session_id
    return JSONResponse(data)


# ── Gene expression ─────────────────────────────────────────────────────────
class GeneRequest(BaseModel):
    session_id: str
    genes:      str
    assay:      str = "RNA"
    slot:       str = "data"


@router.post("/gene")
async def get_gene_expression(req: GeneRequest):
    rds_path = _sessions.get(req.session_id)
    if not rds_path or not os.path.exists(rds_path):
        raise HTTPException(404, "Session not found — please re-upload your file")
    data = _run_r("get_expression.R", [rds_path, req.genes, req.assay, req.slot], timeout=120)
    return JSONResponse(data)


# ── DGE ─────────────────────────────────────────────────────────────────────
class DGERequest(BaseModel):
    session_id: str
    mode:       str = "clusters"
    group_by:   str = "seurat_clusters"
    assay:      str = "RNA"
    slot:       str = "data"
    test_use:   str = "wilcox"
    ident1:     Optional[str] = None
    ident2:     Optional[str] = None
    rm_tcr:     bool = True
    rm_bcr:     bool = True


@router.post("/dge")
async def run_dge(req: DGERequest):
    rds_path = _sessions.get(req.session_id)
    if not rds_path or not os.path.exists(rds_path):
        raise HTTPException(404, "Session not found — please re-upload your file")
    args = [
        rds_path, req.mode, req.group_by, req.assay, req.slot, req.test_use,
        req.ident1 or "", req.ident2 or "",
        "true" if req.rm_tcr else "false",
        "true" if req.rm_bcr else "false",
    ]
    result = _run_r("run_dge.R", args, timeout=600)
    return JSONResponse({
        "markers":      result.get("markers", []),
        "excluded_tcr": result.get("excluded_tcr", []),
        "excluded_bcr": result.get("excluded_bcr", []),
        "species":      result.get("species", "unknown"),
    })
