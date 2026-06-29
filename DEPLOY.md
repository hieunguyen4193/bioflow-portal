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

## 2 — Create data directories

```bash
mkdir -p data/uploads data/results data/explore
```

---

## 3 — Configure environment

### Root `.env` (docker-compose variable substitution)

```bash
cp .env.example .env
```

Edit `.env`:
```dotenv
# Absolute host path to the data directory — must match your machine
BIOFLOW_DATA_DIR=/absolute/path/to/bioflow-portal/data
BIOFLOW_R_SCRIPTS=/absolute/path/to/bioflow-portal/backend/app/r_scripts
```

> **Why host paths?** The backend calls `docker run` via the Docker socket.
> The host Docker daemon interprets volume paths as paths on the *host machine*, not inside the backend container.

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

All required R packages (CellChat, clusterProfiler, msigdbr, org.Hs.eg.db, org.Mm.eg.db, etc.) are baked into a custom Docker image so they never need to be installed at runtime.

```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
```

This takes ~2–5 minutes on first build (compiles CellChat from source). Subsequent builds use the Docker layer cache and finish in seconds.

**Optional — push to a registry so other machines can pull instead of building:**
```bash
docker tag pipeline-portal/r-pipeline:latest yourrepo/r-pipeline:latest
docker push yourrepo/r-pipeline:latest
```

Then on the target machine set in `.env`:
```dotenv
PIPELINE_IMAGE=yourrepo/r-pipeline:latest
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

If R package dependencies changed (e.g. new package added to `pipeline-image/install_packages.R`), rebuild the pipeline image first:
```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
docker compose up --build -d
```

---

## Directory structure after setup

```
bioflow-portal/
├── backend/
│   ├── .env                   ← secret key, SMTP config
│   └── app/r_scripts/         ← R scripts mounted into pipeline containers
├── data/
│   ├── uploads/               ← uploaded input files
│   ├── results/               ← Nextflow pipeline outputs
│   └── explore/               ← Explore page session data and analysis results
├── frontend/
├── nextflow/pipelines/        ← Nextflow pipeline definitions and Rmd reports
├── pipeline-image/
│   ├── Dockerfile             ← extends base image with all R packages baked in
│   └── install_packages.R     ← package list (edit here to add new packages)
├── .env                       ← BIOFLOW_DATA_DIR, BIOFLOW_R_SCRIPTS
└── docker-compose.yml
```

---

## Troubleshooting

### Port already in use
Change the host port in `docker-compose.yml` (left side of `HOST:CONTAINER`):
```yaml
ports:
  - "8080:8000"   # use 8080 instead of 8000
```

### Backend can't connect to database
The `db` healthcheck must pass before the backend starts. Check with:
```bash
docker compose ps
```

### R pipeline fails with "there is no package called 'X'"
The package is missing from the image. Add it to `pipeline-image/install_packages.R` and rebuild:
```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
```

### Nextflow pipeline fails with "Docker not found"
The backend container needs access to the host Docker socket. Confirm this volume is in `docker-compose.yml`:
```yaml
- /var/run/docker.sock:/var/run/docker.sock
```
On Linux with Docker Desktop, enable "Expose daemon on tcp://localhost:2375" in Docker Desktop settings.

### Permission denied on data directories
```bash
chmod -R 777 data/
```
