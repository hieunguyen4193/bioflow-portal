# AnnData Object from 10x CellRanger (Python / scanpy)

Python/scanpy port of `basic_Seurat_single_cell_pipeline`. Same pipeline steps,
same parameters, same skip switches, same output layout — the R/Seurat/Bioconductor
stack is replaced end-to-end with Python/scanpy equivalents. Creates an AnnData
object from 10x CellRanger output and takes it through quality control,
normalisation, dimensionality reduction, clustering and marker-gene detection.

## Input files

| File | Description |
|------|-------------|
| `barcodes.tsv.gz` | Cell barcodes from CellRanger |
| `features.tsv.gz` | Gene / feature list |
| `matrix.mtx.gz`   | Sparse count matrix |

## Pipeline steps

| Step | Description | Optional |
|------|-------------|----------|
| **S1**  | Create AnnData object, apply QC filters (min cells, min/max features, max % MT) | No |
| **S1b** | Downsample cells (by percent or absolute count) | Yes |
| **S2**  | Ambient RNA correction | Yes |
| **S3**  | Doublet detection and removal | Yes |
| **S4**  | Normalisation (LogNormalize / Pearson-residual) | Yes |
| **S5**  | Cell-cycle scoring and regression | Yes |
| **S6**  | Cell-factor regression (custom covariates) | Yes |
| **S7**  | Harmony / Scanorama / BBKNN integration (multi-sample) | Yes |
| **S8**  | UMAP dimensionality reduction and graph-based clustering | Yes |

(Step numbering in the code follows the original R pipeline's internal module
order — S1 through S8a below map onto the table above the same way they do in
`basic_Seurat_single_cell_pipeline`.)

## R → Python tool mapping

Every step keeps the same purpose and the same CLI parameters as the R
pipeline. Where R/Bioconductor has no direct Python equivalent, the closest
established alternative was used — these substitutions are the only real
methodological difference between the two pipelines:

| R / Bioconductor                  | Python equivalent used here                                   | Note |
|------------------------------------|-----------------------------------------------------------------|------|
| Seurat (`CreateSeuratObject`, QC)  | scanpy (`AnnData`, `sc.pp.calculate_qc_metrics`)                | direct equivalent |
| `decontX` (celda)                 | custom lightweight EM re-implementation                        | no official Python port of celda/decontX exists; see `modules/ambient_decontamination` |
| `SoupX`                            | *not implemented*                                               | R pipeline also stops with "not yet implemented" — same behaviour, kept for parity |
| `DoubletFinder`                    | **Scrublet**                                                    | direct equivalent, same per-sample workflow |
| `SCTransform`                      | `sc.experimental.pp.normalize_pearson_residuals`                | statistically equivalent method (Lause/Kobak/Berens 2021) |
| `CellCycleScoring` (Seurat)        | `sc.tl.score_genes_cell_cycle`                                  | same Tirosh et al. 2015 gene lists, see `src/cc_genes.py` |
| `org.Hs.eg.db::mapIds`             | **mygene** (MyGene.info client)                                 | SYMBOL → ENSEMBL lookup for `cc_scoring_mode=ensembl` |
| `HarmonyIntegration` (Seurat)      | **harmonypy**                                                   | exact algorithmic port, same method |
| `CCAIntegration` (Seurat)          | **Scanorama**                                                   | different algorithm, same integration role — not a literal CCA port |
| `RPCAIntegration` (Seurat)         | **BBKNN**                                                       | different algorithm, same integration role — not a literal RPCA port |
| R Markdown report                  | Python script generating a self-contained HTML report           | plots/tables regenerated straight from the final `.h5ad`'s `obs`/`obsm` instead of pre-rendered plot objects |

## Key parameters

Identical to the R pipeline — see `main.nf` for the full parameter list:

- **`min_cells`** — keep features detected in at least this many cells (default: 3)
- **`min_features` / `max_features`** — per-cell feature count thresholds (default: 200 / 5000)
- **`max_mt_pct`** — maximum mitochondrial gene percentage (default: 20%)
- **`sample_name`** — name embedded in all output filenames
- **`outdir`** — output directory name (default: `results`)

## Outputs

All outputs are written under `<outdir>/`:

```
results/
  s1_scanpy/             sample_s1.h5ad, QC plots
  s1b_downsample/        sample_s1b.h5ad
  s2_ambient/            sample_s2.h5ad
  s3_filter/             sample_s3.h5ad
  s4_doublet/            sample_s4.h5ad
  s5_cell_cycle/         sample_s5.h5ad
  s6_cell_cycle_scoring/ sample_s6.h5ad
  s7_regress_out/        sample_s7.h5ad
  s8_umap_clustering/    sample_s8.h5ad
  s8a_report/            sample_preliminary_analysis.html
```

## Notes

- TCR genes (`TRAV`, `TRAJ`, `TRBV`, …) can be excluded at the S1 step.
- Integration steps are skipped automatically when only one sample is present.
- All steps downstream of a skipped step receive the last successfully produced `.h5ad` file.
- This pipeline's Docker image (see `pipeline-image-python/`) is separate from
  the R pipeline's image — build it with the Python package list in
  `src/requirements.txt` before running with the `docker` profile.
- Out of scope for this port: the portal's Explore tab (upload/DGE/pathway/CellChat)
  is still R/`.rds`-only (`backend/app/api/explore.py`, `backend/app/r_scripts/`).
  This pipeline's `.h5ad` output isn't wired into that subsystem — ask if you'd
  like that extended too.
