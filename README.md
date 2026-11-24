# BioInfoLab

A self-hosted web application for interactive analysis of single-cell RNA-seq data (Seurat objects).

## Stack

| Layer | Technology |
|---|---|
| Frontend | React + Vite + Tailwind |
| Backend API | FastAPI (Python) |
| Database | PostgreSQL |
| Auth | JWT |
| Analyses | R (Seurat) scripts run in a Docker image |

## Quick start

```bash
# 1. Copy and fill in environment files
cp .env.example .env                   # set BIOFLOW_DATA_DIR and BIOFLOW_R_SCRIPTS
cp backend/.env.example backend/.env   # set SECRET_KEY; optionally SMTP

# 2. Build the R image used by the analyses (bakes in all required R packages)
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

## Interactive data analysis

The **Interactive data analysis** page lets you upload a Seurat `.rds` file (or load a preset) and explore it interactively. Tabs:

| Tab | Description |
|-----|-------------|
| UMAP | Colour by any metadata column; cluster labels at centroids |
| Feature Plot | Expression of one or more genes (2×2 / 3×3 multi-panel), downloadable as a vector PDF |
| Violin Plot | Per-cluster expression distribution, downloadable as a vector PDF |
| Box Plot | Same per-cluster expression data as Violin Plot, shown as box-and-whisker plots |
| DGE — Clusters | FindAllMarkers — one cluster vs. all others, for every cluster |
| DGE — Conditions | FindMarkers — two user-defined groups within a metadata column |
| Sub-cluster | Subset the sidebar-selected clusters and re-run normalisation/PCA/UMAP/clustering on just those cells |
| Pathway | ORA + GSEA across GO, KEGG, WikiPathways, MSigDB (C1–C8 human; mouse subset + C1–C8 ortholog fallback) |
| CellChat | Cell–cell communication analysis; downloadable HTML report |
| Metadata | Per-column statistical summary of the metadata, with a CSV download of the full per-cell table |
| Guide | Built-in documentation for every tab |

### DGE
- Both DGE tabs share the same backend (Seurat `FindMarkers`/`FindAllMarkers`) and test options: `wilcox` (default), `t`, `MAST`, `DESeq2`
- MAST and DESeq2 run as a cancellable background task with a live R log, since both can take several minutes
- Optional TCR/BCR gene removal (V(D)J gene families) applies to both tabs
- Every run is cached by its full parameter set; DGE — Conditions results are auto-offered to the Pathway tab

### Sub-cluster
- Reuses the sidebar's "Colour by" column and "Subset clusters" checkboxes as the cluster selection to subset — no separate picker
- Re-runs LogNormalize or SCTransform, PCA, UMAP, and graph-based clustering from scratch on just the selected cells
- Runs as a cancellable background task with a live R log (a few minutes, similar to MAST/DESeq2)
- Cached by its full parameter set (clusters, normalisation, PCs, resolution, TCR/BCR removal); each cached run's re-clustered `.rds` can be downloaded

### Pathway
- Runs ORA and GSEA using clusterProfiler
- **Human:** H, C1–C8 MSigDB collections + GO + KEGG + WikiPathways
- **Mouse:** H, mouse-specific subset (M1, M2, M3, M5, M8), plus C1–C8 MSigDB collections via ortholog mapping + GO + KEGG + WikiPathways
- Results shown as a clusterProfiler-style dot plot (x = GeneRatio, size = gene count, colour = p.adjust)
- Download results as CSV or vector PDF (Illustrator-compatible)

### CellChat
- Species auto-detected from gene name casing (fully uppercase → Human)
- Runs in the background with live R log streaming
- Results open as an HTML report in-page, with "Open in new tab" and "Download HTML" buttons
- Cancel button available while running
