# BioInfoLab — Deployment Guide

BioInfoLab runs as three Docker Compose services: `frontend` (Vite), `backend` (FastAPI) and `db` (PostgreSQL). For each analysis the backend starts a short-lived R container from the R image (`pipeline-portal/r-pipeline:latest`) through the host's Docker socket.

## Prerequisites

| Tool | Min version | Install |
|------|------------|---------|
| Docker | 24+ | https://docs.docker.com/get-docker/ |
| Docker Compose | v2 (bundled with Docker Desktop) | included above |
| Git | any | `sudo apt install git` / `brew install git` |

**Linux only:** add your user to the `docker` group so you don't need `sudo`:
```bash
sudo usermod -aG docker $USER && newgrp docker
```

---

## 1 — Clone the repository

```bash
git clone https://github.com/hieunguyen4193/bioflow-portal.git
cd bioflow-portal
```

---

## 2 — Choose a data directory

All app data lives under one directory that you choose: preset objects, uploaded objects, caches and analysis results. It does **not** need to be inside the repo; a dedicated disk or mounted volume is a good choice.

```bash
export BIOFLOW_DATA_DIR=/mnt/bioflow-data
mkdir -p "$BIOFLOW_DATA_DIR"/explore/presets
```

What ends up in it:

```
$BIOFLOW_DATA_DIR/explore/
├── presets/<project>/<name>.rds   ← preset objects, one folder per project
├── <uuid>.rds                     ← objects users uploaded
└── .dge_cache_*, .subcluster_cache_*, module_score_*, …   ← cached analysis results
```

The PostgreSQL data (users, project access) is stored separately, in the Docker volume `pgdata`.

---

## 3 — Configure the environment

### Root `.env`

```bash
cp .env.example .env
```

Edit `.env`:
```dotenv
# Absolute path to the data directory from step 2
BIOFLOW_DATA_DIR=/mnt/bioflow-data

# Absolute host path to the backend's R scripts directory
BIOFLOW_R_SCRIPTS=/absolute/path/to/bioflow-portal/backend/app/r_scripts

# Docker image the R analyses run in
PIPELINE_IMAGE=pipeline-portal/r-pipeline:latest
```

> **Why host paths?** The backend starts R containers with `docker run` through the Docker socket, and the host's Docker daemon reads volume paths as paths on the *host*, not inside the backend container. That is why both paths must be absolute host paths.

### `backend/.env`

```bash
cp backend/.env.example backend/.env
```

Edit `backend/.env`:
```dotenv
DATABASE_URL=postgresql+asyncpg://bioflow:bioflow@db:5432/bioflow

# Signs login tokens. Generate with: openssl rand -hex 32
SECRET_KEY=<paste generated key here>

ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=10080
```

---

## 4 — Build the R image

All R packages the analyses need are baked into one image, so nothing has to be installed while an analysis runs:

```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
```

It extends the base image `tronghieunguyen/single_cell_pipeline` (Seurat 5) with the packages listed in `pipeline-image/install_packages.R`. These include CellChat, clusterProfiler, `org.Hs.eg.db`/`org.Mm.eg.db`, msigdbr, DESeq2, MAST and harmony.

The first build takes a while because it compiles CellChat from source. Later builds use the Docker layer cache.

**To add an R package**, add it to `pipeline-image/install_packages.R` and rebuild. The build only installs packages that are missing.

**To share the image across machines**, push it to a registry:
```bash
docker tag pipeline-portal/r-pipeline:latest yourrepo/r-pipeline:latest
docker push yourrepo/r-pipeline:latest
```
Then set `PIPELINE_IMAGE=yourrepo/r-pipeline:latest` in `.env` on the target machine and run `docker pull yourrepo/r-pipeline:latest` before starting.

---

## 5 — Start the application

```bash
docker compose up --build
```

Or use `./deploy.sh`, which builds the R image only if it is missing and then runs the same command.

| Service | URL |
|---------|-----|
| App | http://localhost:5173 |
| Backend API | http://localhost:8000 |
| API docs | http://localhost:8000/docs |

The frontend calls the backend through Vite's proxy (`/api` → `backend:8000`), so always open the app on port 5173.

---

## 6 — Create the first admin

Register an account on the login page, then make it an admin:

```bash
docker compose exec db psql -U bioflow -d bioflow \
  -c "UPDATE users SET is_admin = true WHERE username = '<username>';"
```

Log out and back in. The **Admin** page now appears in the top bar. Use **Project Access** there to give other users access to preset projects; users only see the presets of projects they have access to.

To add presets, copy `.rds` files into `$BIOFLOW_DATA_DIR/explore/presets/<project>/`. A new project folder shows up in Admin → Project Access automatically.

---

## 7 — Run in the background

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

Stop and **delete the database** (all users and access grants):
```bash
docker compose down -v
```

**After a server reboot** the containers do not start again on their own, because `docker-compose.yml` sets no restart policy. Run `docker compose up -d` again, or add `restart: unless-stopped` to each service in `docker-compose.yml`.

**Dev-mode servers:** the compose file runs the Vite dev server and `uvicorn --reload` against the source code mounted from the repo. Code changes take effect immediately, but this is not a hardened production setup.

---

## Updating to a new version

```bash
git pull
docker compose up --build -d
```

If `pipeline-image/install_packages.R` changed, rebuild the R image as well:
```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
```

Restarting the backend clears in-memory sessions: users have to load their data again, but cached results are kept on disk.

---

## Directory structure

```
bioflow-portal/
├── backend/
│   ├── .env                      ← database URL and token secret
│   ├── app/r_scripts/            ← R scripts (and the CellChat Rmd report), mounted into the R containers
│   └── Dockerfile
├── frontend/
├── pipeline-image/
│   ├── Dockerfile                ← extends the base image with all R packages baked in
│   └── install_packages.R        ← package list (edit here to add packages)
├── .env                          ← BIOFLOW_DATA_DIR, BIOFLOW_R_SCRIPTS, PIPELINE_IMAGE
├── .env.example                  ← template for the above
├── deploy.sh
└── docker-compose.yml
```

---

## New machine checklist

- [ ] Install Docker (24+) and Docker Compose v2
- [ ] `git clone` the repository
- [ ] Choose a data directory and `mkdir -p $BIOFLOW_DATA_DIR/explore/presets`
- [ ] Copy and edit `.env` (`BIOFLOW_DATA_DIR`, `BIOFLOW_R_SCRIPTS`, `PIPELINE_IMAGE`)
- [ ] Copy and edit `backend/.env` (`SECRET_KEY`)
- [ ] Build or pull the R image
- [ ] `docker compose up --build -d`
- [ ] Register an account and make it an admin (step 6)
- [ ] Copy preset `.rds` files into project folders and grant project access

---

## Troubleshooting

### Can't reach the app
Check that all three containers are up:
```bash
docker compose ps
```
If they show `Exited` (for example after a reboot), start them with `docker compose up -d`.

### Port already in use
Change the host port in `docker-compose.yml`:
```yaml
ports:
  - "8080:8000"   # use 8080 instead of 8000
```

### Backend can't connect to the database
The `db` healthcheck must pass before the backend starts. Check with `docker compose ps` and `docker compose logs db`.

### Analysis fails with "there is no package called 'X'"
The package is missing from the R image. Add it to `pipeline-image/install_packages.R` and rebuild:
```bash
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/
```

### Analysis fails with "Docker not found" or can't start a container
The backend starts the R analyses as sibling containers. Confirm this volume is present for the backend in `docker-compose.yml`:
```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

### Analysis can't find the R scripts or the data
`BIOFLOW_R_SCRIPTS` and `BIOFLOW_DATA_DIR` in `.env` must be absolute paths **on the host** (see step 3). Recreate the backend after changing them: `docker compose up -d backend`.

### CellChat report is blank / "Open in new tab" shows nothing
Open the app on port 5173, not 8000. The report is fetched through the frontend's `/api` proxy.

### Permission denied on the data directory
The R containers write results into `$BIOFLOW_DATA_DIR/explore`. Make the directory writable for the user the containers run as, for example with a shared group:
```bash
sudo chgrp -R docker "$BIOFLOW_DATA_DIR" && sudo chmod -R g+rwX "$BIOFLOW_DATA_DIR"
```
