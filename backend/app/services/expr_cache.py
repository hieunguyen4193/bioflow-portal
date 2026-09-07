"""Builder + registry for the memory-mapped gene-expression cache.

A cache entry is keyed by (rds_path, assay, slot) and lives as a pair of files
on disk — a `.json` metadata sidecar and a `.bin` float32 matrix — written by
`load_seurat.R`. Keying off rds_path (not a session id) means a cache built by
one path is immediately visible to the other: the interactive Explore session
flow in app.api.explore, and the admin cache-management endpoints in
app.api.admin, which build caches for preset files directly.
"""
import hashlib
import json
import os
import subprocess
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path

from app.services.presets import EXPLORE_DIR, HOST_EXPLORE
from app.services.r_runner import DOCKER_IMAGE, HOST_SCRIPTS, R_SCRIPTS

# Fixed set the admin picks from for a whole-project cache run — deliberately not
# read off the data (that would mean opening every .rds file in the project just
# to list its assays, defeating the point of a "don't inspect, just cache" bulk
# action). Almost every dataset in this pipeline carries these two assays.
ASSUMED_ASSAYS = ["RNA", "SCT"]
ASSUMED_SLOTS  = ["data", "counts"]

_expr_caches: dict[str, dict] = {}    # rds_path → {(assay, slot): {mat, cells, gene_idx}}
_cache_building: set[tuple] = set()   # {(rds_path, assay, slot)} currently being built
_build_errors: dict[tuple, str] = {}  # {(rds_path, assay, slot)} → last load_seurat.R stderr, if it failed


def get_build_error(rds_path: str, assay: str, slot: str) -> str | None:
    return _build_errors.get((rds_path, assay, slot))


def cache_base_for(rds_path: str) -> str:
    key = hashlib.md5(rds_path.encode()).hexdigest()[:16]
    return os.path.join(EXPLORE_DIR, f".seurat_cache_{key}")


def list_cache_entries(rds_path: str) -> list[dict]:
    """List cached (assay, slot) pairs on disk for this rds_path — pure filesystem
    scan, does not require the cache to be loaded into memory."""
    cache_base = cache_base_for(rds_path)
    parent = Path(cache_base).parent
    prefix = Path(cache_base).name + "_"

    entries = []
    for meta_path in sorted(parent.glob(f"{prefix}*.json")):
        bin_path = meta_path.with_suffix(".bin")
        if not bin_path.exists():
            continue
        try:
            meta = json.loads(meta_path.read_text())
        except Exception:
            continue
        assay_name = meta.get("assay")
        slot_name  = meta.get("slot")
        if not assay_name or not slot_name:
            continue
        entries.append({
            "assay":      assay_name,
            "slot":       slot_name,
            "size_bytes": bin_path.stat().st_size,
        })
    return entries


def is_cached(rds_path: str, assay: str, slot: str) -> bool:
    if _expr_caches.get(rds_path, {}).get((assay, slot)):
        return True
    return any(e["assay"] == assay and e["slot"] == slot for e in list_cache_entries(rds_path))


def is_building(rds_path: str, assay: str, slot: str) -> bool:
    return (rds_path, assay, slot) in _cache_building


def evict(rds_path: str, assay: str | None = None, slot: str | None = None) -> None:
    """Drop the in-memory memmap for one (assay, slot) pair, or all pairs for
    rds_path when assay/slot are omitted. Does not touch files on disk."""
    if assay and slot:
        _expr_caches.get(rds_path, {}).pop((assay, slot), None)
    else:
        _expr_caches.pop(rds_path, None)


def delete_cache(rds_path: str, assay: str | None = None, slot: str | None = None) -> int:
    """Delete cached .bin/.json files on disk for rds_path — one (assay, slot)
    pair, or every pair for this file when both are omitted — and evict the
    matching in-memory memmap(s). Returns the number of files removed."""
    cache_base = cache_base_for(rds_path)
    parent = Path(cache_base).parent
    prefix = Path(cache_base).name + "_"

    if assay and slot:
        paths = [parent / f"{prefix}{assay}_{slot}.bin", parent / f"{prefix}{assay}_{slot}.json"]
    else:
        paths = list(parent.glob(f"{prefix}*.bin")) + list(parent.glob(f"{prefix}*.json"))

    evict(rds_path, assay, slot)

    removed = 0
    for path in paths:
        if path.exists():
            path.unlink()
            removed += 1
    return removed


def delete_project_cache(rds_paths: list[str]) -> int:
    """Delete every cache file for every dataset path given — e.g. all .rds
    files in a project. Returns the total number of files removed."""
    return sum(delete_cache(rds_path) for rds_path in rds_paths)


def load_expr_cache(rds_path: str, cache_base: str) -> None:
    """Memory-map binary expression files written by load_seurat.R.
    Keys in _expr_caches[rds_path] are (assay, slot) tuples.
    Files must have 'assay' and 'slot' fields in their JSON metadata.
    """
    import numpy as np
    assay_data: dict = {}
    parent = Path(cache_base).parent
    prefix = Path(cache_base).name + "_"
    for meta_path in sorted(parent.glob(f"{prefix}*.json")):
        bin_path = meta_path.with_suffix(".bin")
        if not bin_path.exists():
            continue
        try:
            meta = json.loads(meta_path.read_text())
            assay_name = meta.get("assay")
            slot_name  = meta.get("slot")
            if not assay_name or not slot_name:
                continue  # old-format file without assay/slot fields — skip
            n_genes = int(meta["n_genes"])
            n_cells = int(meta["n_cells"])
            mat = np.memmap(str(bin_path), dtype=np.float32, mode="r",
                            shape=(n_genes, n_cells))
            assay_data[(assay_name, slot_name)] = {
                "mat":      mat,
                "cells":    meta["cells"],
                "gene_idx": {g: i for i, g in enumerate(meta["genes"])},
            }
        except Exception:
            continue
    if assay_data:
        existing = _expr_caches.get(rds_path, {})
        existing.update(assay_data)
        _expr_caches[rds_path] = existing


def build_expr_cache_bg(rds_path: str, cache_base: str,
                        required_assay: str, required_slot: str) -> None:
    """Background thread: run load_seurat.R to cache one (assay, slot) pair.

    Errors out (and propagates to R stderr) if the slot is not available in
    the assay — no silent zero-fill.
    """
    cache_key = (rds_path, required_assay, required_slot)

    # Already in memory — nothing to do
    if _expr_caches.get(rds_path, {}).get((required_assay, required_slot)):
        return
    # Another thread is already building this exact pair
    if cache_key in _cache_building:
        return

    _cache_building.add(cache_key)
    _build_errors.pop(cache_key, None)
    try:
        bin_path = Path(f"{cache_base}_{required_assay}_{required_slot}.bin")
        if bin_path.exists():
            load_expr_cache(rds_path, cache_base)
            return

        script = os.path.join(R_SCRIPTS, "load_seurat.R")
        cmd = [
            "docker", "run", "--rm",
            "-v", f"{HOST_EXPLORE}:{EXPLORE_DIR}",
            "-v", f"{HOST_SCRIPTS}:{R_SCRIPTS}",
            DOCKER_IMAGE,
            "Rscript", "--vanilla", script,
            rds_path, cache_base, required_assay, required_slot,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
        if result.returncode == 0:
            load_expr_cache(rds_path, cache_base)
        else:
            _build_errors[cache_key] = result.stderr[-3000:] or result.stdout[-3000:]
    except subprocess.TimeoutExpired:
        _build_errors[cache_key] = "Cache build timed out (30 min)"
    finally:
        _cache_building.discard(cache_key)


def rebuild_cache_bg(rds_path: str, cache_base: str, assay: str, slot: str) -> None:
    """Force a fresh cache build for (rds_path, assay, slot), even if one already
    exists. Deletes the old .bin/.json first — build_expr_cache_bg short-circuits
    and just reloads the existing .bin otherwise, and leaving it in place while
    rebuilding would waste disk. Meant to be run in a background thread, same as
    build_expr_cache_bg."""
    delete_cache(rds_path, assay, slot)
    build_expr_cache_bg(rds_path, cache_base, assay, slot)


# ── Whole-project cache jobs ───────────────────────────────────────────────────
# "Cache this entire project" queues every (file, assay, slot) combination the
# admin picked and runs them one at a time in a single background thread — not
# one docker container per combination in parallel — so a big project doesn't
# pile up dozens of simultaneous `docker run`s (and R processes) on the host.
_project_jobs: dict[str, dict] = {}  # job_id → job state


def _run_project_cache_job(job_id: str, rds_files: list[tuple[str, str]],
                           assays: list[str], slots: list[str]) -> None:
    job = _project_jobs[job_id]
    try:
        for filename, rds_path in rds_files:
            for assay in assays:
                for slot in slots:
                    if job["status"] == "cancelled":
                        return
                    item = {"filename": filename, "assay": assay, "slot": slot, "status": "running"}
                    job["current"] = item
                    job["items"].append(item)

                    if is_cached(rds_path, assay, slot):
                        item["status"] = "skipped"
                        item["message"] = "already cached"
                        continue

                    cache_base = cache_base_for(rds_path)
                    build_expr_cache_bg(rds_path, cache_base, assay, slot)

                    if is_cached(rds_path, assay, slot):
                        item["status"] = "done"
                    else:
                        item["status"] = "error"
                        item["error"] = get_build_error(rds_path, assay, slot) or "unknown error"
    finally:
        job["current"] = None
        if job["status"] != "cancelled":
            job["status"] = "done"
        job["finished_at"] = datetime.now(timezone.utc).isoformat()


def start_project_cache_job(project: str, rds_files: list[tuple[str, str]],
                            assays: list[str], slots: list[str]) -> str:
    """rds_files: list of (filename, rds_path) for every dataset in the project."""
    job_id = str(uuid.uuid4())
    _project_jobs[job_id] = {
        "job_id":      job_id,
        "project":     project,
        "assays":      assays,
        "slots":       slots,
        "total":       len(rds_files) * len(assays) * len(slots),
        "items":       [],
        "current":     None,
        "status":      "running",
        "created_at":  datetime.now(timezone.utc).isoformat(),
    }
    threading.Thread(
        target=_run_project_cache_job,
        args=(job_id, rds_files, assays, slots),
        daemon=True,
    ).start()
    return job_id


def get_project_job(job_id: str) -> dict | None:
    return _project_jobs.get(job_id)


def list_project_jobs() -> list[dict]:
    return sorted(_project_jobs.values(), key=lambda j: j["created_at"], reverse=True)


def cancel_project_job(job_id: str) -> bool:
    job = _project_jobs.get(job_id)
    if not job or job["status"] != "running":
        return False
    job["status"] = "cancelled"
    return True
