# BioFlow Portal

A self-hosted web application for running Nextflow bioinformatics pipelines, with SLURM HPC support.

## Stack

| Layer | Technology |
|---|---|
| Frontend | React + Vite + Tailwind |
| Backend API | FastAPI (Python) |
| Job queue | Celery + Redis |
| Database | PostgreSQL |
| Auth | JWT |
| HPC | Nextflow + SLURM |

## Quick start (local / Docker)

```bash
cp backend/.env backend/.env   # edit SMTP settings if needed
docker compose up --build
```

- Frontend: http://localhost:5173
- API docs:  http://localhost:8000/docs

## Running on HPC

The Celery worker must run on a node with access to the SLURM `sbatch` command and a shared filesystem visible to both the web server and compute nodes.

1. Install Nextflow on the head node: `curl -s https://get.nextflow.io | bash`
2. Run the worker outside Docker: `celery -A app.workers.celery_app worker --loglevel=info`
3. Set `NEXTFLOW_PIPELINES_DIR` in `.env` to the shared path where pipelines live.
4. Adjust `nextflow/conf/slurm.config` (queue name, memory, modules/containers).

## Adding a new pipeline

1. Create `nextflow/pipelines/<pipeline_id>/main.nf`
2. Add an entry to `backend/app/api/pipelines.py` → `PIPELINE_REGISTRY`
3. The worker auto-maps `--barcodes`, `--features`, `--matrix` by filename; for other file types extend the mapping in `backend/app/workers/tasks.py`.

## Pipelines included

### `seurat_from_10x`

Creates a Seurat object from 10x CellRanger output (barcodes / features / matrix triplet).

**Inputs:** `barcodes.tsv.gz`, `features.tsv.gz`, `matrix.mtx.gz`

**Outputs:**
- `<sample>_seurat.rds` — filtered Seurat object
- `qc_violin_prefilter.png` — QC violin plots before filtering
- `qc_violin_postfilter.png` — QC violin plots after filtering
- `qc_scatter.png` — nCount vs nFeature scatter
- `qc_stats.csv` — summary table (cells retained, medians)

**Parameters:**

| Key | Default | Description |
|---|---|---|
| `sample_name` | `sample` | Name embedded in the Seurat object |
| `min_cells` | `3` | Min cells expressing a feature |
| `min_features` | `200` | Min features per cell |
| `max_features` | `5000` | Max features per cell |
| `max_mt_pct` | `20` | Max % mitochondrial reads |
