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
| Pipelines | Nextflow DSL2 + Docker |

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

---

## Pipelines

### `basic_Seurat_single_cell_pipeline`

Creates a Seurat object from 10x CellRanger output and takes it through quality control, normalisation, dimensionality reduction, clustering, and marker-gene detection.

**Inputs:** `barcodes.tsv.gz`, `features.tsv.gz`, `matrix.mtx.gz`

**Steps:**

| Step | Description | Optional |
|------|-------------|----------|
| S1 | Create Seurat object; apply QC filters (min cells, min/max features, max % MT) | No |
| S1b | Downsample cells (by percent or absolute count) | Yes |
| S2 | Ambient RNA correction (decontX / SoupX) | Yes |
| S3 | Doublet detection (scDblFinder / DoubletFinder) | Yes |
| S4 | Normalisation (LogNormalize / SCTransform) + cell-cycle scoring | Yes |
| S5 | CC pre-processing and regression | Yes |
| S6 | Cell-cycle scoring (alternate) | Yes |
| S7 | Regress out covariates | Yes |
| S8 | UMAP + graph-based clustering | Yes |

**Key parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `sample_name` | `sample` | Name embedded in output filenames |
| `min_cells` | `3` | Min cells expressing a feature |
| `min_features` / `max_features` | `200` / `5000` | Per-cell feature thresholds |
| `max_mt_pct` | `20` | Max % mitochondrial reads |
| `cluster_resolution` | `0.5` | Seurat clustering resolution |

**Outputs:** per-step RDS files, QC plots, UMAP plots, marker CSV — all under `results/`.

---

### `fragmentomics_TF_features`

Generates a suite of cfDNA fragmentomics features from WGS BAM or CRAM files: chromosome features, CNA, TFBS coverage profiles, WPS/IFS/FDI, and RFE. All scripts are bundled in the pipeline directory — no external source checkout required.

**Samplesheet:**
```csv
SampleID,Path
SAMPLE_01,/path/to/SAMPLE_01.bam
```
Set `--input_type cram` for CRAM input (Step 0 converts it to BAM first).

**Steps:**

| Step | Description | Optional |
|------|-------------|----------|
| Step 0 | CRAM → BAM conversion | Yes (CRAM only) |
| Step 01 | Sort/index BAM, split into short/long/full sub-BAMs, convert to BEDPE fragment file, genome coverage | No |
| Step 02 | Chromosome-level fragment features (std, avg, Shannon entropy) | Yes |
| Step 03 | CNA features for TFBS coverage (100 kb + 1 Mb bins) | Yes |
| Step 04 | Coverage profile features across TFBS sites | Yes |
| Step 05 | WPS / IFS / FDI features across TFBS sites | Yes |
| Step 06 | RFE (Relative Fragment End) features across TFBS sites | Yes |

**Key parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `input_type` | `bam` | `bam` or `cram` |
| `resource_dir` | `/Users/hieunguyen/storage/resources` | Directory containing `hg19.fa`, `rpr_map_EXP0779.bed`, `TFBS/` |
| `nthreads` | `4` | samtools threads per sample |
| `short_lower` / `short_upper` | `50` / `150` | Short fragment range (bp) |
| `long_lower` / `long_upper` | `151` / `350` | Long fragment range (bp) |
| `min_flen` / `max_flen` | `50` / `350` | Fragment length filter for BEDPE |
| `markdup` | `false` | Mark duplicates with Picard |

**Outputs:**
```
results/
  step01_process_bam/<SampleID>/    sorted BAM, short/long BAMs, splitChroms, frag bed.gz, genomeCov
  step02_chromosome_features/       *_std_avg_shannon.tsv
  step03_cna_features/<SampleID>/   *.bin100kb.bed, *.bin1M.bed
  step04_coverage_profile/<SampleID>/  coverage profile features per TFBS
  step05_wps_ifs_fdi/<SampleID>/    WPS/IFS/FDI features per TFBS
  step06_rfe_features/<SampleID>/   RFE features per TFBS
```

**Docker image:** `tronghieunguyen/wgs-fragmentomics-features:latest`

---

### `fragmentomics_bulk_features`

Computes bulk cfDNA fragmentomics features (fragment length distribution, end motif, nucleosome distance) from BAM files or pre-computed FLEN/EM/ND tables.

**Modes:**

| Mode | Samplesheet columns | Description |
|------|---------------------|-------------|
| `from_bam` | `SampleID, Path` (BAM) | Runs Step 01 to extract fragment file, then computes EM + ND + bulk features |
| `from_frag_file` | `SampleID, Path` (FLEN_EM_ND.tsv) | Skips fragment extraction; uses pre-computed table directly |

**Key parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `mode` | `from_bam` | `from_bam` or `from_frag_file` |
| `resource_dir` | `/Users/hieunguyen/storage/resources` | Directory containing `hg19.fa`, `rpr_map_Budhraja_STM2023.bed` |
| `min_flen` / `max_flen` | `50` / `350` | Fragment length bounds |

**Outputs:**
```
results/
  bulk_features/<SampleID>/    per-sample bulk feature matrices
  bulk_features/<SampleID>/    *_FLEN_EM_ND.tsv  (from_bam mode only)
```

---

### `fragmentomics_binwise_features`

Computes genome-wide per-bin read counts from short-fragment, long-fragment, and full BAM files using an R script. Supports two samplesheet modes — if short/long BAMs are already available they are used directly; otherwise the pipeline splits the full BAM automatically.

**Samplesheet (pre-split BAMs available):**
```csv
SampleID,short_bam,long_bam,full_bam
sample01,/path/to/short.bam,/path/to/long.bam,/path/to/full.bam
```

**Samplesheet (auto-split from full BAM)** — `full_bam` or `path` column accepted:
```csv
SampleID,Path
sample01,/path/to/full.bam
```
When `short_bam` / `long_bam` columns are absent the pipeline splits the full BAM at `split_cutoff` bp (default 150) into short (≤ cutoff) and long (> cutoff) sub-BAMs before computing features.

Each BAM file must have a `.bai` index alongside it.

**Key parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `split_cutoff` | `150` | Fragment length cutoff (bp) used when auto-splitting (short ≤ cutoff, long > cutoff) |
| `outdir` | `results` | Output directory |

**Outputs:**
```
results/
  split_bam/<SampleID>/        short.bam, long.bam (auto-split mode only)
  binwise_features/<SampleID>/ per-bin count matrices
```

---

### `fragmentomics_enrich_features`

Filters BAM files or fragment tables to enrich for specific sub-populations of cfDNA fragments. Three independent filter modes are available.

**Modes:**

| Mode | Input | Description |
|------|-------|-------------|
| `filter_flen` | BAM | Splits BAM into short (≤ 150 bp), long (151–350 bp), and full (50–350 bp) sub-BAMs |
| `filter_bed` | BAM + BED | Retains only reads overlapping a supplied BED file (e.g., TFBS, enhancers) |
| `filter_nd` | FLEN_EM_ND.tsv | Filters fragment rows by nucleosome-distance range (`nd_min`–`nd_max`) |

**Samplesheet formats:**

`filter_flen` and `filter_nd`:
```csv
SampleID,Path
sample01,/path/to/file
```

`filter_bed`:
```csv
SampleID,Path,BED
sample01,/path/to/sample01.bam,/path/to/regions.bed
```

**Key parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `mode` | `filter_flen` | `filter_flen`, `filter_bed`, or `filter_nd` |
| `bed_file` | — | Server-side BED path (used in `filter_bed` mode if not in samplesheet) |
| `nd_min` / `nd_max` | `0` / `50` | Nucleosome-distance range (for `filter_nd`) |
