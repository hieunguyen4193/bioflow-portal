# BioInfoLab

A self-hosted web application for interactive analysis of single-cell RNA-seq data stored as Seurat objects (`.rds`). Users load an object, either one they upload or a shared preset, and explore it in the browser: UMAPs, gene expression plots, differential expression, sub-clustering, pathway enrichment and cell–cell communication. The analyses run as R (Seurat) scripts on the server.

## Stack

| Layer | Technology |
|---|---|
| Frontend | React + Vite + Tailwind |
| Backend API | FastAPI (Python) |
| Database | PostgreSQL (users and project access) |
| Auth | JWT |
| Analyses | R scripts (Seurat 5) run in Docker containers started by the backend |

## Quick start

```bash
# 1. Copy and fill in the environment files
cp .env.example .env                   # set BIOFLOW_DATA_DIR and BIOFLOW_R_SCRIPTS
cp backend/.env.example backend/.env   # set SECRET_KEY

# 2. Build the R image the analyses run in (bakes in all required R packages)
docker build -t pipeline-portal/r-pipeline:latest ./pipeline-image/

# 3. Start everything
docker compose up --build
```

| Service | URL |
|---------|-----|
| App | http://localhost:5173 |
| API docs | http://localhost:8000/docs |

Then register an account on the login page and make it an admin (see [Users and access](#users-and-access)).

See [DEPLOY.md](DEPLOY.md) for the full setup, running in the background, updating and troubleshooting.

---

## Interactive data analysis

The **Interactive data analysis** page is the main part of the app. It opens on a start screen with two ways to load data:

- **Upload** a Seurat `.rds` file by drag and drop.
- **Load a preset**: pick a project, then a file. **Download** saves that preset's `.rds` file.
- **Remote storage (Coscine / S3)**: a separate source on the start screen; see [Remote storage](#remote-storage-coscine--s3).

The left sidebar holds the shared settings that most tabs use: reduction, assay and slot, "Colour by", "Split by", and the "Subset clusters" checkboxes. The tabs:

| Tab | What it does |
|-----|-------------|
| UMAP | Cells in any 2-D reduction, coloured by a metadata column, with cluster labels at the centroids |
| Feature Plot | Expression of one or more genes on the UMAP, one panel per gene; vector PDF export |
| Violin Plot | Per-cluster expression distribution; vector PDF export |
| Box Plot | The same data as Violin Plot, as box-and-whisker plots |
| Module Score | Upload gene modules (CSV/XLS/XLSX, one column per module) and score cells with `AddModuleScore`; heatmap, feature and violin views |
| DGE — Clusters | `FindAllMarkers`: every cluster against all others |
| DGE — Conditions | `FindMarkers`: two groups of a metadata column |
| DGE — Condition2 | `FindMarkers` between two groups inside a subset of cells (for example two samples within one cluster) |
| Sub-cluster | Subset the selected clusters and redo normalisation, (re-)integration, PCA, UMAP and clustering on those cells |
| Re-cluster | Re-run clustering of the whole object at a new resolution, as a new metadata column |
| Pathway | ORA + GSEA across GO, KEGG, WikiPathways and MSigDB |
| CellChat | Cell–cell communication analysis, rendered as an HTML report |
| Metadata | Per-column summary of the metadata, plus a CSV download of the full per-cell table |
| Guide | Built-in documentation for every tab |

Long analyses (DGE with MAST or DESeq2, Sub-cluster, Re-cluster, Module Score, Pathway, CellChat) run as cancellable background tasks with a live R log. Results are cached on the server by their full parameter set. Each tab has a "Cached results" list for reloading or deleting earlier runs, and running the same settings again returns the cached result.

### DGE
- All three DGE tabs use Seurat `FindMarkers`/`FindAllMarkers` with the test options `wilcox` (default), `t`, `MAST` and `DESeq2`.
- `min.pct` changes which genes are tested; the p-value and log2FC thresholds only filter what is shown.
- Optional removal of TCR/BCR V(D)J gene families.
- On the `SCT` assay, `PrepSCTFindMarkers` runs on the full object before any subsetting, so DGE — Condition2 works on integrated SCT data.
- Results of DGE — Conditions and DGE — Condition2 are offered to the Pathway tab.

### Sub-cluster
- Uses the sidebar's "Colour by" column and "Subset clusters" checkboxes as the selection.
- Re-runs LogNormalize or SCTransform, PCA, UMAP and graph-based clustering from scratch on the selected cells.
- **Integration:** an integrated object has to be re-integrated after subsetting, or the new UMAP and clusters are no longer batch-corrected. Choose None, CCA, RPCA, Harmony, or **CCA + RPCA + Harmony** (the same as the pipeline that built the object), plus the sample column to integrate over (default `name`). The tab detects which integrations the object already has (the `integrated.cca`, `integrated.rpca` and `harmony` reductions) and preselects them.
  - With a single method, the result has one `umap` and `seurat_clusters`.
  - With all three, each method gets its own `<method>_UMAP` and `<method>.cluster.<resolution>` column; the preview has UMAP and "Colour by" pickers.
- The re-clustered object can be downloaded as `.rds` or saved as a new preset.
- RPCA needs enough anchors between samples; on very small subsets it can fail with "Number of anchor cells is less than k.weight". Use CCA or Harmony alone in that case.

### Re-cluster
- Runs `FindClusters` at a new resolution, either on the object's stored neighbour graph or on a graph rebuilt from a chosen reduction (for example CCA or RPCA).
- The result is a new metadata column (default `recluster_res.<resolution>`). For presets it can also be written back into the preset `.rds`, so server-side analyses and other users can use it.

### Pathway
- ORA and GSEA with clusterProfiler.
- **Human:** MSigDB H + C1–C8, GO, KEGG, WikiPathways.
- **Mouse:** MSigDB H, the mouse-specific collections (M1, M2, M3, M5, M8), C1–C8 via ortholog mapping, GO, KEGG, WikiPathways.
- Gene lists come from a DGE run, a pasted list, or an uploaded CSV.
- Results as clusterProfiler-style dot plots; download as CSV or vector PDF.

### CellChat
- Species is detected from gene-name casing (mostly uppercase means human) and can be overridden.
- The HTML report opens in the page, with "Open in new tab" and "Download HTML".

---

## Presets

Presets are Seurat `.rds` files on the server that users can load without uploading. They live in project folders:

```
$BIOFLOW_DATA_DIR/explore/presets/<project>/<name>.rds
```

To add one, copy an `.rds` file into a project folder, or use **Save as preset** on a Sub-cluster result. Users only see the projects they have access to (see below).

---

## Remote storage (Coscine / S3)

The start screen's **Remote storage (Coscine / S3)** tab browses any S3-compatible bucket, such as a Coscine RDS-S3 resource, and loads `.rds` files from it.

1. Enter the endpoint (default `https://global.datastorage.nrw`), bucket name, access key and secret key. For Coscine these are on the resource's settings page; use the **read** key pair.
2. **Connect**, browse folders, and click **Load** next to an `.rds` file.
3. The server downloads the file (with a progress bar and Cancel) and then opens it like an upload.

How it works:
- Keys are sent with each request and are never stored on the server. The browser keeps them for the tab session, or in local storage if you tick "Remember on this browser". "Forget keys" clears them.
- A loaded file is copied once to `$BIOFLOW_DATA_DIR/explore/remote/<hash>/`. Later loads of the same file reuse that copy unless the remote file changed (ETag or size), and cached analysis results are kept with it.
- BioInfoLab only reads from remote storage; it never writes back.
- Only `https://` endpoints are accepted. To restrict which hosts users may connect to, set `REMOTE_S3_ALLOWED_HOSTS` (comma-separated host names) in the backend's environment.

---

## Users and access

- Anyone can register an account on the login page.
- Admins see an **Admin** page with:
  - **Project Access**: which users can see which preset projects. Admins see every project.
  - **Expression Cache**: pre-build the gene-expression cache for preset datasets, so gene plots load fast without opening the dataset first.
- There is no admin account by default. To make a registered user an admin:

  ```bash
  docker compose exec db psql -U bioflow -d bioflow \
    -c "UPDATE users SET is_admin = true WHERE username = '<username>';"
  ```

---

## Repository layout

```
bioflow-portal/
├── backend/
│   ├── app/
│   │   ├── api/              ← FastAPI routes: auth, explore (analyses), admin
│   │   ├── r_scripts/        ← R scripts for each analysis + the CellChat Rmd report
│   │   └── services/         ← presets, project access, expression cache, R runner
│   └── Dockerfile
├── frontend/                 ← React app (the analysis page is src/pages/ExplorePage.tsx)
├── pipeline-image/           ← R image the analyses run in; edit install_packages.R to add packages
├── docker-compose.yml
├── deploy.sh                 ← builds the R image if missing, then starts the app
├── .env.example
└── DEPLOY.md
```
