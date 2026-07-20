FROM python:3.11-slim

# System libraries needed by scikit-misc (scanpy's seurat_v3 HVG flavor) and matplotlib.
# libgsl-dev alone pulls in whatever runtime libgslN package matches this base image's
# Debian release — the exact soname (libgsl27, libgsl28, ...) shifts across releases,
# so it must not be pinned here.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        build-essential \
        libgsl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY install_packages.txt /tmp/install_packages.txt
RUN pip install --no-cache-dir -r /tmp/install_packages.txt && rm /tmp/install_packages.txt
