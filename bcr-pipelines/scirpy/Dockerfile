# scirpy BCR/TCR repertoire analysis image.
FROM python:3.11-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        scirpy==0.20.1 \
        scanpy==1.10.3 \
        leidenalg \
        python-igraph \
        pandas \
        matplotlib
