# Seurat Object from 10x CellRanger

Creates a Seurat object from the 10x CellRanger output (barcodes / features / matrix triplet) and takes it through quality control, normalisation, dimensionality reduction, clustering and marker-gene detection.

## Input files

| File | Description |
|------|-------------|
| `barcodes.tsv.gz` | Cell barcodes from CellRanger |
| `features.tsv.gz` | Gene / feature list |
| `matrix.mtx.gz`   | Sparse count matrix |

## Pipeline steps

| Step | Description | Optional |
|------|-------------|----------|
| **S1**  | Create Seurat object, apply QC filters (min cells, min/max features, max % MT) | No |
| **S1b** | Downsample cells (by percent or absolute count) | Yes |
| **S2**  | Ambient RNA correction (decontX / SoupX) | Yes |
| **S3**  | Doublet detection and removal (scDblFinder / DoubletFinder) | Yes |
| **S4**  | Normalisation (LogNormalize / SCTransform) | Yes |
| **S5**  | Cell-cycle scoring and regression | Yes |
| **S6**  | Cell-factor regression (custom covariates) | Yes |
| **S7**  | Harmony / CCA / RPCA integration (multi-sample) | Yes |
| **S8**  | UMAP dimensionality reduction and graph-based clustering | Yes |

## Key parameters

- **`min_cells`** — keep features detected in at least this many cells (default: 3)
- **`min_features` / `max_features`** — per-cell feature count thresholds (default: 200 / 5000)
- **`max_mt_pct`** — maximum mitochondrial gene percentage (default: 20%)
- **`sample_name`** — name embedded in all output filenames
- **`outdir`** — output directory name (default: `results`)

## Outputs

All outputs are written under `<outdir>/`:

```
results/
  s1_create_seurat/     sample_s1.rds, QC plots
  s1b_downsample/       sample_s1b.rds
  s2_ambient_rna/       sample_s2.rds
  s3_doublet/           sample_s3.rds
  s4_normalisation/     sample_s4.rds
  s5_cell_cycle/        sample_s5.rds
  s6_regress_out/       sample_s6.rds
  s7_integration/       sample_s7.rds
  s8_umap_clustering/   sample_s8.rds, UMAP plots, marker CSV
```

## Notes

- TCR genes (`TRAV`, `TRAJ`, `TRBV`, …) can be excluded at the S1 step.
- Integration steps (S7) are skipped automatically when only one sample is present.
- All steps downstream of a skipped step receive the last successfully produced RDS file.
