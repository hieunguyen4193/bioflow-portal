# BioFlow Portal — Deployment Guide

## Prerequisites

Install the following on the target machine:

| Tool | Version | Install |
|------|---------|---------|
| Docker | 24+ | https://docs.docker.com/get-docker/ |
| Docker Compose | v2 (bundled with Docker Desktop) | included above |
| Git | any | `sudo apt install git` / `brew install git` |

> **Linux only:** add your user to the docker group so you don't need `sudo`:
> ```bash
> sudo usermod -aG docker $USER && newgrp docker
> ```

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

```bash
cp .env.example .env
cp backend/.env.example backend/.env
```

**Edit `.env`** (root — controls docker-compose variable substitution):
```dotenv
# Must be the absolute host path to the data directory
BIOFLOW_DATA_DIR=/absolute/path/to/bioflow-portal/data
```

**Edit `backend/.env`**:
```dotenv
# Generate a secure key:  openssl rand -hex 32
SECRET_KEY=<paste generated key here>

# Absolute host path to the r_scripts directory
HOST_R_SCRIPTS=/absolute/path/to/bioflow-portal/backend/app/r_scripts

# Optional — fill in only if you want email notifications
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your@email.com
SMTP_PASSWORD=your-app-password
EMAILS_FROM=noreply@bioflow.local
```

> **Why host paths?** The backend container calls `docker run` via the Docker socket. The host Docker daemon interprets volume paths as paths on the *host machine*, not inside the container.

---

## 4 — (Optional) Mount your resource data

If you run the **Fragmentomics** pipelines, they need reference files (genome FASTA, BED files, etc.).
Mount the resource directory by adding a volume to the `backend` service in `docker-compose.yml`:

```yaml
volumes:
  ...
  - /path/to/your/resources:/data/resources
```

Then update the `resource_dir` parameter when submitting a Fragmentomics job to `/data/resources`.

---

## 5 — Start the application

```bash
docker compose up --build
```

First launch takes ~5–10 minutes (pulls images, builds containers, installs R packages via Nextflow on first pipeline run).

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
docker compose logs -f backend    # backend only
docker compose logs -f            # all services
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

---

## Troubleshooting

### Port already in use
Change the host port in `docker-compose.yml` (left side of `HOST:CONTAINER`):
```yaml
ports:
  - "8080:8000"   # use 8080 instead of 8000
```

### Backend can't connect to database
Wait a few seconds — the `db` healthcheck must pass before the backend starts. Run `docker compose ps` to check service status.

### Nextflow pipeline fails with "Docker not found"
The backend container needs access to the host Docker socket. Make sure this volume is present in `docker-compose.yml`:
```yaml
- /var/run/docker.sock:/var/run/docker.sock
```
On Linux, Docker Desktop users may need to enable "Expose daemon on tcp://localhost:2375" in Docker Desktop settings.

### Permission denied on data directories
```bash
chmod -R 777 data/
```
