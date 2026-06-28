"""Run Nextflow pipelines in a background thread — no queue needed."""
import os
import re
import signal
import subprocess
import threading

_ANSI_ESCAPE = re.compile(r'\x1b\[[0-9;]*[A-Za-z]|\x1b[()][AB012]|\x1b[=>]')

def _strip_ansi(text: str) -> str:
    return _ANSI_ESCAPE.sub('', text)
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from app.core.config import settings
from app.models.job import Job
import app.models.user  # noqa: F401

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


def _build_cmd(pipeline: str, params: dict, input_files: list, job_base: str, user_outdir: str, resume: bool = False) -> list[str]:
    outdir_path = os.path.join(job_base, user_outdir)
    os.makedirs(outdir_path, exist_ok=True)

    pipeline_dir = os.path.join(settings.NEXTFLOW_PIPELINES_DIR, pipeline)
    cmd = [
        settings.NEXTFLOW_BIN, "run", pipeline_dir,
        "--outdir", outdir_path,
        "-work-dir", os.path.join(job_base, "work"),
    ]
    if resume:
        cmd.append("-resume")

    for f in input_files:
        fname    = os.path.basename(f)
        abs_path = os.path.join(settings.UPLOAD_DIR, f)
        # samplesheet-mode pipelines upload a CSV; others use the 10x triplet
        if fname.endswith(".csv") or "samplesheet" in fname.lower():
            cmd += ["--samplesheet", abs_path]
        elif "barcodes" in fname:
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
                job.log = _strip_ansi(stdout)
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
