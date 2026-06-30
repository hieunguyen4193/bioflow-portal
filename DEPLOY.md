# Pipeline Portal — Deployment Guide

## Prerequisites

| Tool | Min version | Install |
|------|------------|---------|
| Docker | 24+ | https://docs.docker.com/get-docker/ |
| Docker Compose | v2 (bundled with Docker Desktop) | included above |
| Git | any | `sudo apt install git` / `brew install git` |

**Linux only** — add your user to the docker group so you don't need `sudo`:
```bash
sudo usermod -aG docker $USER && newgrp docker
```

---

## 1 — Clone the repository

```bash
git clone <your-repo-url> bioflow-portal
cd bioflow-portal
```

---

## 2 — Choose a data directory and create it

All uploads, pipeline results, and Explore session data (including saved presets) are stored under one directory that you choose. It does **not** need to live inside the repo — point it at a dedicated disk, a mounted volume, or wherever you want persistent storage to live.

```bash
# Example: a dedicated path outside the repo
export BIOFLOW_DATA_DIR=/mnt/bioflow-data
mkdir -p "$BIOFLOW_DATA_DIR"/{uploads,results,explore}
```

(You can also just use a path inside the repo, e.g. `bioflow-portal/data`, if you don't need it elsewhere — that's only a default suggestion, not a requirement.)

---

## 3 — Configure environment

### Root `.env`

```bash
cp .env.example .env
```

Edit `.env`:
```dotenv
# Absolute path to the data directory you chose in step 2 — can be anywhere
BIOFLOW_DATA_DIR=/mnt/bioflow-data

# Absolute host path to the R scripts directory
BIOFLOW_R_SCRIPTS=/absolute/path/to/bioflow-portal/backend/app/r_scripts

# Docker image used for all R analysis jobs (pathway analysis, CellChat)
PIPELINE_IMAGE=pipeline-portal/r-pipeline:latest
```

> **Why host paths?** The backend calls `docker run` via the Docker socket.
> The host Docker daemon interprets volume paths as paths on the *host machine*, not inside the backend container. `docker-compose.yml` also mounts `${BIOFLOW_DATA_DIR}/uploads`, `${BIOFLOW_DATA_DIR}/results`, and `${BIOFLOW_DATA_DIR}/explore` directly into the backend container, so this one variable controls all data storage.

### `backend/.env`

```bash
cp backend/.env.example backend/.env
```

Edit `backend/.env`:
```dotenv
DATABASE_URL=postgresql+asyncpg://bioflow:bioflow@db:5432/bioflow

# Generate with: openssl rand -hex 32
SECRET_KEY=<paste generated key here>

ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=10080

UPLOAD_DIR=/data/uploads
RESULTS_DIR=/data/results
NEXTFLOW_BIN=nextflow
NEXTFLOW_PIPELINES_DIR=/nextflow/pipelines

# Optional — fill in only if you want email notifications
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your@email.com
SMTP_PASSWORD=your-app-password
EMAILS_FROM=noreply@bioflow.local
```

---

## 4 — Build the R pipeline image

All required R packages are baked into a custom Docker image so they never need to be installed at runtime:

```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
```

Packages included: `CellChat`, `clusterProfiler`, `org.Hs.eg.db`, `org.Mm.eg.db`, `msigdbr`, `clusterProfiler`, `ComplexHeatmap`, `BiocNeighbors`, `ggplot2`, `rmarkdown`, and more.

Build time: ~2–5 minutes on first build (compiles CellChat from source). Subsequent builds use the Docker layer cache and finish in seconds.

**To share across machines — push to a registry:**
```bash
docker tag pipeline-portal/r-pipeline:latest yourrepo/r-pipeline:latest
docker push yourrepo/r-pipeline:latest
```

Then on the target machine set in `.env`:
```dotenv
PIPELINE_IMAGE=yourrepo/r-pipeline:latest
```
And pull before starting:
```bash
docker pull yourrepo/r-pipeline:latest
```

**To add a new R package**, edit `pipeline-image/install_packages.R` and rebuild:
```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
```

---

## 5 — Start the application

```bash
docker compose up --build
```

First launch pulls base images and builds the frontend and backend containers (~3–5 min).

| Service | URL |
|---------|-----|
| Frontend | http://localhost:5173 |
| Backend API | http://localhost:8000 |
| API docs | http://localhost:8000/docs |

---

## 6 — Run in the background (production)

```bash
docker compose up --build -d
```

View logs:
```bash
docker compose logs -f backend   # backend only
docker compose logs -f           # all services
```

Stop:
```bash
docker compose down
```

Stop and wipe the database:
```bash
docker compose down -v
```

---

## Updating to a new version

```bash
git pull
docker compose up --build -d
```

If R package dependencies changed (new package added to `pipeline-image/install_packages.R`):
```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
docker compose up --build -d
```

---

## Directory structure

```
bioflow-portal/
├── backend/
│   ├── .env                      ← secret key, SMTP config
│   └── app/r_scripts/            ← R scripts mounted into pipeline containers at runtime
├── frontend/
├── nextflow/
│   └── pipelines/                ← Nextflow pipeline definitions and Rmd reports
├── pipeline-image/
│   ├── Dockerfile                ← extends base image with all R packages baked in
│   └── install_packages.R        ← package list (edit here to add new packages)
├── .env                          ← BIOFLOW_DATA_DIR, BIOFLOW_R_SCRIPTS, PIPELINE_IMAGE
├── .env.example                  ← template for the above
└── docker-compose.yml

$BIOFLOW_DATA_DIR/                ← lives wherever you chose in step 2, not necessarily in the repo
├── uploads/                      ← uploaded input files
├── results/                      ← Nextflow pipeline outputs
└── explore/                      ← Explore page session data, presets, and analysis results
```

---

## New machine checklist

- [ ] Install Docker (24+) and Docker Compose v2
- [ ] `git clone` the repository
- [ ] Choose a data directory and `mkdir -p $BIOFLOW_DATA_DIR/{uploads,results,explore}`
- [ ] Copy and edit `.env` (set `BIOFLOW_DATA_DIR`, `BIOFLOW_R_SCRIPTS`, `PIPELINE_IMAGE`)
- [ ] Copy and edit `backend/.env` (set `SECRET_KEY`)
- [ ] Build or pull the R pipeline image
- [ ] `docker compose up --build -d`

---

## Troubleshooting

### Port already in use
Change the host port in `docker-compose.yml`:
```yaml
ports:
  - "8080:8000"   # use 8080 instead of 8000
```

### Backend can't connect to database
The `db` healthcheck must pass before the backend starts. Check status:
```bash
docker compose ps
```

### R pipeline fails with "there is no package called 'X'"
The package is missing from the image. Add it to `pipeline-image/install_packages.R` and rebuild:
```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
```

### CellChat report shows nothing / "Open in new tab" is blank
Make sure the Vite dev server is running (frontend container). The `/explore` route is proxied through Vite to the backend — if you access the frontend directly on port 8000 it will not work.

### Nextflow pipeline fails with "Docker not found"
Confirm this volume is present in `docker-compose.yml`:
```yaml
- /var/run/docker.sock:/var/run/docker.sock
```
On Linux with Docker Desktop, enable "Expose daemon on tcp://localhost:2375" in Docker Desktop settings.

### Permission denied on data directories
```bash
chmod -R 777 data/
```
