# Pipeline Portal

A self-hosted web application for running Nextflow bioinformatics pipelines and interactively exploring single-cell RNA-seq data.

## Stack

| Layer | Technology |
|---|---|
| Frontend | React + Vite + Tailwind |
| Backend API | FastAPI (Python) |
| Job queue | Celery + Redis |
| Database | PostgreSQL |
| Auth | JWT |
| Pipelines | Nextflow DSL2 + Docker |

## Quick start

```bash
# 1. Copy and fill in environment files
cp .env.example .env                   # set BIOFLOW_DATA_DIR and BIOFLOW_R_SCRIPTS
cp backend/.env.example backend/.env   # set SECRET_KEY; optionally SMTP

# 2. Build the R pipeline image (bakes in all required R packages)
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/

# 3. Start everything
docker compose up --build
```

| Service | URL |
|---------|-----|
| Frontend | http://localhost:5173 |
| API docs | http://localhost:8000/docs |

See [DEPLOY.md](DEPLOY.md) for full deployment instructions including production setup and new-machine checklist.

---

## Explore page

The **Explore** tab lets you upload a Seurat `.rds` file (or load a preset) and interactively explore it without running a pipeline. Tabs:

| Tab | Description |
|-----|-------------|
| UMAP | Colour by any metadata column; cluster labels at centroids |
| Feature Plot | Expression of one or more genes (2×2 / 3×3 multi-panel) |
| Violin Plot | Per-cluster expression distribution |
| Dot Plot | Dot size = % expressing, colour = average expression |
| Heatmap | Top marker genes per cluster |
| DGE | Differential gene expression (clusters or conditions) |
| Pathway Analysis | ORA + GSEA across GO, KEGG, WikiPathways, MSigDB (C1–C8 human; M1–M8 mouse) |
| CellChat | Cell–cell communication analysis; downloadable HTML report |
| Guide | Built-in documentation for every tab |

### Pathway Analysis
- Runs ORA and GSEA using clusterProfiler
- **Human:** H, C1–C8 MSigDB collections + GO + KEGG + WikiPathways
- **Mouse:** H, M1–M8, C1–C8 MSigDB collections (with ortholog mapping fallback) + GO + KEGG + WikiPathways
- Results shown as a clusterProfiler-style dot plot (x = GeneRatio, size = gene count, colour = p.adjust)
- Download results as CSV or vector PDF (Illustrator-compatible)

### CellChat
- Species auto-detected from gene name casing (fully uppercase → Human)
- Runs in the background with live R log streaming
- Results open as an HTML report in-page, with "Open in new tab" and "Download HTML" buttons
- Cancel button available while running

---

## Running on HPC

The Celery worker must run on a node with SLURM `sbatch` access and a shared filesystem.

1. Install Nextflow on the head node: `curl -s https://get.nextflow.io | bash`
2. Run the worker outside Docker: `celery -A app.workers.celery_app worker --loglevel=info`
3. Set `NEXTFLOW_PIPELINES_DIR` in `backend/.env` to the shared pipeline path.
4. Adjust `nextflow/conf/slurm.config` for your cluster (queue, memory, modules).

---

## Adding a new pipeline

1. Create `nextflow/pipelines/<pipeline_id>/main.nf`
2. Add an entry to `backend/app/api/pipelines.py` → `PIPELINE_REGISTRY`
3. The worker auto-maps `--barcodes`, `--features`, `--matrix` by filename; extend `backend/app/workers/tasks.py` for other file types.

---

## Pipelines

### `basic_Seurat_single_cell_pipeline`

Creates a Seurat object from 10x CellRanger output and takes it through QC, normalisation, dimensionality reduction, clustering, and marker-gene detection.

**Inputs:** `barcodes.tsv.gz`, `features.tsv.gz`, `matrix.mtx.gz`

| Step | Description | Optional |
|------|-------------|----------|
| S1 | Create Seurat object; QC filters (min cells, min/max features, max % MT) | No |
| S1b | Downsample cells | Yes |
| S2 | Ambient RNA correction (decontX / SoupX) | Yes |
| S3 | Doublet detection (scDblFinder / DoubletFinder) | Yes |
| S4 | Normalisation (LogNormalize / SCTransform) + cell-cycle scoring | Yes |
| S5 | CC pre-processing and regression | Yes |
| S6 | Cell-cycle scoring (alternate) | Yes |
| S7 | Regress out covariates | Yes |
| S8 | UMAP + graph-based clustering | Yes |

**Key parameters:** `sample_name`, `min_cells` (3), `min_features` / `max_features` (200 / 5000), `max_mt_pct` (20), `cluster_resolution` (0.5)

**Outputs:** per-step RDS files, QC plots, UMAP plots, marker CSV under `results/`.

---

### `fragmentomics_TF_features`

Generates cfDNA fragmentomics features from WGS BAM/CRAM: chromosome features, CNA, TFBS coverage, WPS/IFS/FDI, and RFE.

**Samplesheet:**
```csv
SampleID,Path
SAMPLE_01,/path/to/SAMPLE_01.bam
```
Set `--input_type cram` for CRAM input.

| Step | Description | Optional |
|------|-------------|----------|
| Step 0 | CRAM → BAM | Yes |
| Step 01 | Sort/index, split by fragment size, BEDPE, genome coverage | No |
| Step 02 | Chromosome-level fragment features | Yes |
| Step 03 | CNA features (100 kb + 1 Mb bins) | Yes |
| Step 04 | Coverage profile features across TFBS | Yes |
| Step 05 | WPS / IFS / FDI features across TFBS | Yes |
| Step 06 | RFE features across TFBS | Yes |

**Docker image:** `tronghieunguyen/wgs-fragmentomics-features:latest`

---

### `fragmentomics_bulk_features`

Computes bulk cfDNA fragmentomics features (fragment length distribution, end motif, nucleosome distance).

| Mode | Input | Description |
|------|-------|-------------|
| `from_bam` | BAM | Extracts fragment file then computes features |
| `from_frag_file` | FLEN_EM_ND.tsv | Uses pre-computed table directly |

---

### `fragmentomics_binwise_features`

Computes per-genomic-bin read counts across short, long, and full BAM files.

Accepts pre-split BAMs (`SampleID, short_bam, long_bam, full_bam`) or a single full BAM (auto-split at `split_cutoff`, default 150 bp).

---

### `fragmentomics_enrich_features`

Filters BAM files or fragment tables to enrich for specific fragment sub-populations.

| Mode | Input | Description |
|------|-------|-------------|
| `filter_flen` | BAM | Splits into short / long / full sub-BAMs |
| `filter_bed` | BAM + BED | Keeps reads overlapping a BED region |
| `filter_nd` | FLEN_EM_ND.tsv | Filters by nucleosome-distance range |
