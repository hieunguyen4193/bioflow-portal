"""Shared "run an R script in the pipeline container and parse its JSON stdout"
helper — used by the interactive Explore session flow and by admin endpoints
that need to invoke R scripts directly against a preset path (no session).
"""
import json
import os
import subprocess

from fastapi import HTTPException

from app.services.presets import EXPLORE_DIR, HOST_EXPLORE

DOCKER_IMAGE = os.environ.get("PIPELINE_IMAGE", "tronghieunguyen/single_cell_pipeline")

HOST_SCRIPTS = os.environ.get("HOST_R_SCRIPTS", "")
R_SCRIPTS    = os.environ.get("R_SCRIPTS_DIR", "/app/app/r_scripts")

# Fall back HOST_SCRIPTS to R_SCRIPTS if not overridden (works when host path == container path)
if not HOST_SCRIPTS:
    HOST_SCRIPTS = R_SCRIPTS


def parse_json_line(json_line: str) -> dict | list:
    # R prints deferred warnings (accumulated via options(warn=0)) right after the
    # script's final cat(toJSON(...)), which has no trailing newline — so a warning
    # can land glued onto the same line with no separator. json.loads would then
    # fail with "Extra data" even though the JSON itself is well-formed; raw_decode
    # parses just the leading JSON value and ignores whatever garbage follows it.
    return json.JSONDecoder().raw_decode(json_line.strip())[0]


def run_r(script_name: str, args: list[str], timeout: int = 300) -> dict | list:
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
        return parse_json_line(json_line)
    except json.JSONDecodeError as exc:
        raise HTTPException(500, f"R parse error: {exc}\nstdout[:500]: {result.stdout[:500]}")
