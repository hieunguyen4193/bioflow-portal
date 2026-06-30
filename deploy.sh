#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export BIOFLOW_DATA_DIR="/mnt/storage/hieu/bioflow-portal/data"
export BIOFLOW_R_SCRIPTS="${SCRIPT_DIR}/backend/app/r_scripts"

PIPELINE_IMAGE="pipeline-portal/r-pipeline:latest"

# Build the R pipeline image only if it doesn't already exist on this machine
if ! sudo docker image inspect "$PIPELINE_IMAGE" > /dev/null 2>&1; then
    echo "Building R pipeline image (first-time setup, may take 15-30 min)..."
    sudo docker build -t "$PIPELINE_IMAGE" "${SCRIPT_DIR}/pipeline-image/"
else
    echo "R pipeline image already present, skipping build."
fi

sudo -E docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up
