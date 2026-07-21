"""Shared preset-directory path/listing logic used by both explore.py and admin.py."""
import os
from pathlib import Path

_host_data = os.environ.get("HOST_DATA_DIR", "").rstrip("/")
HOST_EXPLORE = f"{_host_data}/explore" if _host_data else "/data/explore"

EXPLORE_DIR = os.environ.get("EXPLORE_DIR") or HOST_EXPLORE
PRESETS_DIR = os.path.join(EXPLORE_DIR, "presets")


def list_project_names() -> list[str]:
    os.makedirs(PRESETS_DIR, exist_ok=True)
    return sorted(p.name for p in Path(PRESETS_DIR).iterdir() if p.is_dir())
