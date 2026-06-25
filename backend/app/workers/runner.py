"""Run Nextflow pipelines in a background thread — no queue needed."""
import os
import subprocess
import threading
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from app.core.config import settings
from app.models.job import Job
import app.models.user  # noqa: F401

_sync_url = settings.DATABASE_URL.replace("postgresql+asyncpg://", "postgresql+psycopg2://")
_engine = create_engine(_sync_url, pool_pre_ping=True)


def _db() -> Session:
    return Session(_engine)


def _update_job(job_id: str, **kwargs):
    with _db() as db:
        job = db.get(Job, job_id)
        if job:
            for k, v in kwargs.items():
                setattr(job, k, v)
            db.commit()


def _run(job_id: str):
    with _db() as db:
        job = db.get(Job, job_id)
        if not job:
            return
        pipeline    = job.pipeline
        params      = dict(job.params)
        input_files = list(job.input_files)
        user_id     = job.user_id

    output_dir  = os.path.join(user_id, job_id)
    job_base    = os.path.join(settings.RESULTS_DIR, output_dir)
    os.makedirs(job_base, exist_ok=True)

    # Let user name the results subfolder; default to "results" if blank
    user_outdir = params.pop("outdir", "") or "results"
    # Sanitise: no absolute paths or directory traversal
    user_outdir = user_outdir.strip("/").replace("..", "").strip("/") or "results"
    outdir_path = os.path.join(job_base, user_outdir)
    os.makedirs(outdir_path, exist_ok=True)

    _update_job(job_id, status="running", output_dir=output_dir)

    pipeline_dir = os.path.join(settings.NEXTFLOW_PIPELINES_DIR, pipeline)
    cmd = [
        settings.NEXTFLOW_BIN, "run", pipeline_dir,
        "-profile", "docker",
        "--outdir", outdir_path,
        "-work-dir", os.path.join(job_base, "work"),
    ]

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

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=job_base)
        log  = proc.stdout + "\n" + proc.stderr
        status = "done" if proc.returncode == 0 else "failed"
        _update_job(job_id, status=status, log=log)
    except Exception as exc:
        _update_job(job_id, status="failed", log=str(exc))


def launch(job_id: str):
    t = threading.Thread(target=_run, args=(job_id,), daemon=True)
    t.start()
