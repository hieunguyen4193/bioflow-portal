"""Interactive exploration API — upload a Seurat RDS and explore it."""
import json
import os
import subprocess
import threading
import uuid
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel

router = APIRouter(prefix="/explore", tags=["explore"])

_sessions: dict[str, str] = {}   # session_id → absolute rds path (host path)
_pathway_tasks: dict[str, dict] = {}  # task_id → {status, results, error}

DOCKER_IMAGE = os.environ.get("PIPELINE_IMAGE", "tronghieunguyen/single_cell_pipeline")

# HOST_DATA_DIR is always the host-machine absolute path (set in docker-compose).
# We use it both to derive the container-internal explore path and for docker run -v mounts.
_host_data   = os.environ.get("HOST_DATA_DIR", "").rstrip("/")
HOST_EXPLORE = f"{_host_data}/explore" if _host_data else "/data/explore"
HOST_SCRIPTS = os.environ.get("HOST_R_SCRIPTS", "")

# Container-internal paths (for file I/O inside the backend container).
# If EXPLORE_DIR is explicitly set use it; otherwise derive from HOST_DATA_DIR so the
# path works even before the container is recreated with the new volume layout.
EXPLORE_DIR  = os.environ.get("EXPLORE_DIR") or HOST_EXPLORE
PRESETS_DIR  = os.path.join(EXPLORE_DIR, "presets")
R_SCRIPTS    = os.environ.get("R_SCRIPTS_DIR", "/app/app/r_scripts")

# Fall back HOST_SCRIPTS to R_SCRIPTS if not overridden (works when host path == container path)
if not HOST_SCRIPTS:
    HOST_SCRIPTS = R_SCRIPTS


def _run_r(script_name: str, args: list[str], timeout: int = 300) -> dict | list:
    container_script = os.path.join(R_SCRIPTS, script_name)   # path inside the spawned R container
    cmd = [
        "docker", "run", "--rm",
        "-v", f"{HOST_EXPLORE}:{EXPLORE_DIR}",
        "-v", f"{HOST_SCRIPTS}:{R_SCRIPTS}",
        DOCKER_IMAGE,
        "Rscript", "--vanilla", container_script, *args,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        raise HTTPException(500, f"R error:\n{result.stderr[-3000:]}")
    json_line = next(
        (l for l in result.stdout.splitlines() if l.strip().startswith(("{", "["))),
        None,
    )
    if not json_line:
        raise HTTPException(500, f"R parse error: no JSON in output\nstdout[:500]: {result.stdout[:500]}")
    try:
        return json.loads(json_line)
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


# ── Pathway Analysis ─────────────────────────────────────────────────────────
class PathwayRequest(BaseModel):
    session_id:  str
    csv_data:    str        # JSON-encoded list of row dicts (the DGE markers table)
    species:     str = "auto"
    pval_cutoff: float = 0.05


def _run_pathway_background(task_id: str, csv_path: str, outdir: str, pval: float, species: str):
    container_script = os.path.join(R_SCRIPTS, "run_pathway_analysis.R")
    log_path = os.path.join(outdir, "run.log")
    cmd = [
        "docker", "run", "--rm",
        "-v", f"{HOST_EXPLORE}:{EXPLORE_DIR}",
        "-v", f"{HOST_SCRIPTS}:{R_SCRIPTS}",
        DOCKER_IMAGE,
        "Rscript", "--vanilla", container_script,
        csv_path, outdir, str(pval), species,
    ]
    try:
        with open(log_path, "w") as log_f:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            _pathway_tasks[task_id]["proc"] = proc
            stdout_chunks = []
            for line in proc.stdout:
                if _pathway_tasks[task_id].get("status") == "cancelled":
                    proc.kill()
                    return
                log_f.write(line)
                log_f.flush()
                stdout_chunks.append(line)
                _pathway_tasks[task_id]["log"] = "".join(stdout_chunks)
            proc.wait(timeout=1800)

        if _pathway_tasks[task_id].get("status") == "cancelled":
            return
        full_output = "".join(stdout_chunks)
        json_line = next((l for l in reversed(full_output.splitlines()) if l.strip().startswith("{")), None)

        if proc.returncode != 0 or not json_line:
            _pathway_tasks[task_id].update({"status": "error", "error": full_output[-4000:]})
            return
        parsed = json.loads(json_line)
        _pathway_tasks[task_id].update({"status": "done", "results": parsed})
    except subprocess.TimeoutExpired:
        proc.kill()
        _pathway_tasks[task_id].update({"status": "error", "error": "Pathway analysis timed out (30 min)"})
    except Exception as exc:
        _pathway_tasks[task_id].update({"status": "error", "error": str(exc)})
    finally:
        _pathway_tasks[task_id].pop("proc", None)


@router.post("/pathway")
async def start_pathway_analysis(req: PathwayRequest):
    if req.session_id not in _sessions:
        raise HTTPException(404, "Session not found")
    if req.species not in ("hsa", "mmu", "auto"):
        raise HTTPException(400, "species must be 'hsa', 'mmu', or 'auto'")

    task_id = str(uuid.uuid4())
    task_dir = os.path.join(EXPLORE_DIR, f"pathway_{task_id}")
    os.makedirs(task_dir, exist_ok=True)

    # Write the DGE CSV passed from the frontend
    csv_path = os.path.join(task_dir, "input_genes.csv")
    rows = json.loads(req.csv_data)
    if not rows:
        raise HTTPException(400, "Gene list is empty")
    import csv as _csv
    with open(csv_path, "w", newline="") as f:
        writer = _csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    _pathway_tasks[task_id] = {"status": "running"}
    thread = threading.Thread(
        target=_run_pathway_background,
        args=(task_id, csv_path, task_dir, req.pval_cutoff, req.species),
        daemon=True,
    )
    thread.start()
    return JSONResponse({"task_id": task_id})


@router.get("/pathway/{task_id}")
async def get_pathway_result(task_id: str):
    task = _pathway_tasks.get(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")
    response = {"status": task.get("status"), "log": task.get("log", "")}
    if task.get("status") == "done":
        response["results"] = task.get("results")
    if task.get("status") == "error":
        response["error"] = task.get("error")
    return JSONResponse(response)


@router.post("/pathway/{task_id}/cancel")
async def cancel_pathway(task_id: str):
    task = _pathway_tasks.get(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")
    if task.get("status") != "running":
        raise HTTPException(400, "Task is not running")
    proc = task.get("proc")
    if proc:
        proc.kill()
    task.update({"status": "cancelled"})
    return JSONResponse({"status": "cancelled"})


# ── CellChat Analysis ─────────────────────────────────────────────────────────
_cellchat_tasks: dict[str, dict] = {}

CELLCHAT_RMD = os.environ.get(
    "CELLCHAT_RMD",
    "/nextflow/pipelines/cellchat/rmd/CellChat_single_analysis.Rmd",
)
HOST_CELLCHAT_RMD = os.environ.get(
    "HOST_CELLCHAT_RMD",
    os.path.join(
        os.environ.get("HOST_DATA_DIR", "").replace("/data", ""),
        "nextflow/pipelines/cellchat/rmd/CellChat_single_analysis.Rmd",
    ),
)

# Serve rendered HTML files from the explore dir
from fastapi.responses import FileResponse

@router.get("/cellchat/html/{task_id}")
async def get_cellchat_html(task_id: str):
    task = _cellchat_tasks.get(task_id)
    if not task or task.get("status") != "done":
        raise HTTPException(404, "Report not ready")
    html_path = task.get("html", "").replace(HOST_EXPLORE, EXPLORE_DIR)
    if not os.path.exists(html_path):
        raise HTTPException(404, "HTML file not found")
    return FileResponse(html_path, media_type="text/html")


class CellChatRequest(BaseModel):
    session_id:     str
    sample_id:      str = "ALL"
    filter10cells:  str = "NoFilter"   # "Filter10" or "NoFilter"
    reduction_name: str = "umap"
    cluster_name:   str = "seurat_clusters"
    input_spec:     str = "Human"      # "Human" or "Mouse"


def _run_cellchat_background(task_id: str, rds_path: str, outdir: str, req: dict):
    container_script = os.path.join(R_SCRIPTS, "run_cellchat.R")
    log_path = os.path.join(outdir, "run.log")

    host_base = os.environ.get("HOST_DATA_DIR", "").rstrip("/").replace("/data", "")

    cmd = [
        "docker", "run", "--rm",
        "-v", f"{HOST_EXPLORE}:{EXPLORE_DIR}",
        "-v", f"{HOST_SCRIPTS}:{R_SCRIPTS}",
        "-v", f"{host_base}/nextflow:/nextflow",
        DOCKER_IMAGE,
        "Rscript", "--vanilla", container_script,
        rds_path, outdir,
        req["sample_id"], req["filter10cells"],
        req["reduction_name"], req["cluster_name"],
        req["input_spec"], CELLCHAT_RMD,
    ]
    try:
        with open(log_path, "w") as log_f:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            _cellchat_tasks[task_id]["proc"] = proc
            chunks = []
            for line in proc.stdout:
                if _cellchat_tasks[task_id].get("status") == "cancelled":
                    proc.kill()
                    return
                log_f.write(line)
                log_f.flush()
                chunks.append(line)
                _cellchat_tasks[task_id]["log"] = "".join(chunks)
            proc.wait(timeout=3600)

        if _cellchat_tasks[task_id].get("status") == "cancelled":
            return
        full_output = "".join(chunks)
        json_line = next((l for l in reversed(full_output.splitlines()) if l.strip().startswith("{")), None)

        if proc.returncode != 0 or not json_line:
            _cellchat_tasks[task_id].update({"status": "error", "error": full_output[-4000:]})
            return
        parsed = json.loads(json_line)
        _cellchat_tasks[task_id].update({"status": "done", "html": parsed.get("html", "")})
    except subprocess.TimeoutExpired:
        proc.kill()
        _cellchat_tasks[task_id].update({"status": "error", "error": "CellChat timed out (60 min)"})
    except Exception as exc:
        _cellchat_tasks[task_id].update({"status": "error", "error": str(exc)})
    finally:
        _cellchat_tasks[task_id].pop("proc", None)


@router.post("/cellchat")
async def start_cellchat(req: CellChatRequest):
    rds_path = _sessions.get(req.session_id)
    if not rds_path or not os.path.exists(rds_path):
        raise HTTPException(404, "Session not found — please re-upload your file")

    task_id  = str(uuid.uuid4())
    task_dir = os.path.join(EXPLORE_DIR, f"cellchat_{task_id}")
    os.makedirs(task_dir, exist_ok=True)

    _cellchat_tasks[task_id] = {"status": "running"}
    thread = threading.Thread(
        target=_run_cellchat_background,
        args=(task_id, rds_path, task_dir, req.model_dump()),
        daemon=True,
    )
    thread.start()
    return JSONResponse({"task_id": task_id})


@router.get("/cellchat/{task_id}")
async def get_cellchat_status(task_id: str):
    task = _cellchat_tasks.get(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")
    result = {"status": task.get("status"), "log": task.get("log", "")}
    if task.get("status") == "done":
        result["report_url"] = f"/explore/cellchat/html/{task_id}"
    if task.get("status") == "error":
        result["error"] = task.get("error")
    return JSONResponse(result)


@router.post("/cellchat/{task_id}/cancel")
async def cancel_cellchat(task_id: str):
    task = _cellchat_tasks.get(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")
    if task.get("status") != "running":
        raise HTTPException(400, "Task is not running")
    proc = task.get("proc")
    if proc:
        proc.kill()
    task.update({"status": "cancelled"})
    return JSONResponse({"status": "cancelled"})
