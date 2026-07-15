FROM python:3.11-slim

# System libraries needed by igraph/leidenalg (clustering) and matplotlib.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        build-essential \
        libgsl27 \
        libgsl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY install_packages.txt /tmp/install_packages.txt
RUN pip install --no-cache-dir -r /tmp/install_packages.txt && rm /tmp/install_packages.txt
