"""Run Nextflow pipelines in a background thread — no queue needed."""
import os
import re
import shutil
import signal
import subprocess
import threading
from pathlib import Path

_ANSI_ESCAPE = re.compile(r'\x1b\[[0-9;]*[A-Za-z]|\x1b[()][AB012]|\x1b[=>]')

def _strip_ansi(text: str) -> str:
    return _ANSI_ESCAPE.sub('', text)
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from app.core.config import settings
from app.models.job import Job
from app.services.presets import PRESETS_DIR
import app.models.user  # noqa: F401

# Pipelines whose S8/S8a step produces a Seurat .rds object that can be saved
# into Explore's preset library — mirrors PRESET_SAVEABLE_PIPELINES on the frontend.
PRESET_SAVEABLE_PIPELINES = {"basic_Seurat_single_cell_pipeline"}

_sync_url = settings.DATABASE_URL.replace("postgresql+asyncpg://", "postgresql+psycopg2://")
_engine = create_engine(_sync_url, pool_pre_ping=True)

# job_id → Popen handle for jobs running in this process instance
_procs: dict[str, subprocess.Popen] = {}
_procs_lock = threading.Lock()


def _db() -> Session:
    return Session(_engine)


def _update_job(job_id: str, **kwargs):
    with _db() as db:
        job = db.get(Job, job_id)
        if job:
            for k, v in kwargs.items():
                setattr(job, k, v)
            db.commit()


def _kill_by_pid(pid: int):
    """Send SIGTERM to the process group of the given PID."""
    try:
        os.killpg(os.getpgid(pid), signal.SIGTERM)
    except (ProcessLookupError, OSError):
        # Process may have already exited; try direct kill as fallback
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, OSError):
            pass


def _signal_job(job_id: str, new_status: str) -> bool:
    """
    Find the running Nextflow process and send SIGTERM, then update status.
    Looks in the in-memory _procs dict first; falls back to the PID stored in
    celery_task_id (survives backend restarts).
    Always updates the DB status so the UI reflects the change.
    """
    pid: int | None = None

    with _procs_lock:
        proc = _procs.get(job_id)
        if proc:
            pid = proc.pid

    if pid is None:
        # Try PID stored in DB (set when process was launched)
        with _db() as db:
            job = db.get(Job, job_id)
            if job and job.celery_task_id:
                try:
                    pid = int(job.celery_task_id)
                except ValueError:
                    pass

    if pid is not None:
        _kill_by_pid(pid)

    # Always update status regardless of whether we found the process —
    # the user clearly wants to stop/pause it.
    _update_job(job_id, status=new_status)
    return True


def _save_preset_output(outdir_path: str, preset_project: str, preset_filename: str) -> str | None:
    """Copy the S8 Seurat object(s) produced by a run into Explore's preset
    library, so they show up on the Explore page's preset picker.
    Returns an error message on failure, None on success."""
    if not preset_project or not preset_filename:
        return "Missing project or file name"
    if any(c in preset_project for c in ("/", "\\")) or any(c in preset_filename for c in ("/", "\\")):
        return "Project/file name cannot contain '/' or '\\'"

    rds_files = sorted(Path(outdir_path).glob("s8_umap_clustering/*_s8.rds"))
    if not rds_files:
        return "No S8 output (s8_umap_clustering/*_s8.rds) found to save as a preset"

    dest_dir = os.path.join(PRESETS_DIR, preset_project)
    os.makedirs(dest_dir, exist_ok=True)

    try:
        if len(rds_files) == 1:
            shutil.copyfile(rds_files[0], os.path.join(dest_dir, f"{preset_filename}.rds"))
        else:
            # samplesheet mode with multiple samples — keep them distinct
            for f in rds_files:
                sample = f.name[: -len("_s8.rds")]
                shutil.copyfile(f, os.path.join(dest_dir, f"{preset_filename}_{sample}.rds"))
    except OSError as exc:
        return str(exc)
    return None


def _build_cmd(pipeline: str, params: dict, input_files: list, job_base: str, user_outdir: str, resume: bool = False) -> list[str]:
    outdir_path = os.path.join(job_base, user_outdir)
    os.makedirs(outdir_path, exist_ok=True)

    pipeline_dir = os.path.join(settings.NEXTFLOW_PIPELINES_DIR, pipeline)
    cmd = [
        settings.NEXTFLOW_BIN, "run", pipeline_dir,
        "--outdir", outdir_path,
        "-work-dir", os.path.join(job_base, "work"),
        "-profile", "docker",
    ]
    if resume:
        cmd.append("-resume")

    csv_file = next(
        (f for f in input_files if os.path.basename(f).endswith(".csv") or "samplesheet" in os.path.basename(f).lower()),
        None,
    )
    if csv_file:
        # Samplesheet mode: only forward the CSV itself — any triplet files
        # sitting alongside it (multi-sample uploads) are per-sample and are
        # resolved from inside the CSV's rows via --input_dir, not by name.
        abs_csv = os.path.join(settings.UPLOAD_DIR, csv_file)
        cmd += ["--samplesheet", abs_csv, "--input_dir", os.path.dirname(abs_csv)]
    else:
        for f in input_files:
            fname    = os.path.basename(f)
            abs_path = os.path.join(settings.UPLOAD_DIR, f)
            if "barcodes" in fname:
                cmd += ["--barcodes", abs_path]
            elif "features" in fname or "genes" in fname:
                cmd += ["--features", abs_path]
            elif "matrix" in fname:
                cmd += ["--matrix", abs_path]

    for k, v in params.items():
        if v == "" or v is None:
            continue
        sv = str(v).strip().lower()
        if sv == "true":
            cmd += [f"--{k}", "true"]
        elif sv == "false":
            cmd += [f"--{k}", "false"]
        else:
            cmd += [f"--{k}", str(v)]

    return cmd


def _run(job_id: str, resume: bool = False):
    with _db() as db:
        job = db.get(Job, job_id)
        if not job:
            return
        pipeline    = job.pipeline
        params      = dict(job.params)
        input_files = list(job.input_files)
        user_id     = job.user_id

    output_dir = os.path.join(user_id, job_id)
    job_base   = os.path.join(settings.RESULTS_DIR, output_dir)
    os.makedirs(job_base, exist_ok=True)

    user_outdir = params.pop("outdir", "") or "results"
    user_outdir = user_outdir.strip("/").replace("..", "").strip("/") or "results"

    # Not real pipeline params — pop them out so they never reach `nextflow run` as
    # bogus --save_preset/--preset_project/--preset_filename flags.
    save_preset     = str(params.pop("save_preset", "")).strip().lower() == "true"
    preset_project  = str(params.pop("preset_project", "")).strip()
    preset_filename = str(params.pop("preset_filename", "")).strip()

    outdir_path = os.path.join(job_base, user_outdir)

    _update_job(job_id, status="running", output_dir=output_dir)

    cmd = _build_cmd(pipeline, params, input_files, job_base, user_outdir, resume=resume)

    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, cwd=job_base, start_new_session=True,
        )
        with _procs_lock:
            _procs[job_id] = proc

        # Persist PID so stop/pause work even after a backend restart
        _update_job(job_id, celery_task_id=str(proc.pid))

        stdout, _ = proc.communicate()

        with _procs_lock:
            _procs.pop(job_id, None)

        # If status was already changed to paused/cancelled by a signal, don't overwrite
        with _db() as db:
            job = db.get(Job, job_id)
            if job and job.status == "running":
                status = "done" if proc.returncode == 0 else "failed"
                job.status = status
                log = _strip_ansi(stdout)
                if status == "done" and save_preset and pipeline in PRESET_SAVEABLE_PIPELINES:
                    err = _save_preset_output(outdir_path, preset_project, preset_filename)
                    log += (
                        f"\n\n[preset] Failed to save output as preset: {err}" if err
                        else f"\n\n[preset] Saved output to preset library: {preset_project}/{preset_filename}.rds"
                    )
                job.log = log
                db.commit()
            elif job:
                job.log = _strip_ansi((job.log or "") + "\n" + stdout)
                db.commit()

    except Exception as exc:
        with _procs_lock:
            _procs.pop(job_id, None)
        _update_job(job_id, status="failed", log=str(exc))


def launch(job_id: str):
    t = threading.Thread(target=_run, args=(job_id,), daemon=True)
    t.start()


def stop_job(job_id: str) -> bool:
    return _signal_job(job_id, "cancelled")


def pause_job(job_id: str) -> bool:
    return _signal_job(job_id, "paused")


def resume_job(job_id: str) -> bool:
    """Re-launch a paused job with Nextflow -resume (reuses completed work cache)."""
    with _db() as db:
        job = db.get(Job, job_id)
        if not job or job.status != "paused":
            return False
    t = threading.Thread(target=_run, args=(job_id, True), daemon=True)
    t.start()
    return True
