# BCR repertoire analysis — scirpy

Runs [scirpy](https://scverse.org/scirpy/) (part of the scverse ecosystem) on
single-cell BCR data from 10x Genomics `cellranger vdj`. Unlike the
Immcantation pipeline, scirpy trusts Cell Ranger's own V(D)J gene calls
(no independent IgBLAST reannotation) and defines clonotypes across the
whole concatenated dataset rather than per subject.

## Input

`samplesheet.csv` columns:

| Column | Description |
|---|---|
| `SampleID` | Unique sample identifier |
| `contig_annotations` | `outs/filtered_contig_annotations.csv` from `cellranger vdj` |
| `subject` | *(optional)* passthrough grouping label carried into `adata.obs["subject"]`; defaults to `SampleID` when blank |

## Steps

| Step | Description | Optional |
|------|-------------|----------|
| S1 | Load + concatenate all samples' 10x VDJ contigs into one AnnData (`scirpy.io.read_10x_vdj`) | No |
| S2 | Chain QC (`chain_qc`), keep BCR cells, optionally drop multichain/unpaired cells | No |
| S3 | Clonotype definition — exact (`define_clonotypes`) or similarity-based clusters (`define_clonotype_clusters`) | No |
| S4 | Clonal expansion categories | No |
| S5 | Alpha diversity per sample | No |
| S6 | Pairwise repertoire overlap between samples (auto no-ops for a single sample) | No |
| S7 | V/J gene usage (heavy = VDJ_1, light = VJ_1) + CDR3 length spectratype | No |
| S8 | Static self-contained HTML report | Yes |

## Key parameters

- `remove_multichain` / `require_paired`: chain QC filtering strictness
- `clustering_mode`: `clonotypes` (exact nt identity) or `clonotype_clusters` (similarity-based)
- `sequence` / `metric`: `nt`/`aa` and `identity`/`hamming`/`levenshtein`/`alignment` — only used when `clustering_mode = clonotype_clusters` (exact clonotypes always use nt/identity)
- `receptor_arms` / `dual_ir`: how multi-chain cells are handled during clonotyping
- `diversity_metric`: `normalized_shannon_entropy`, `gini_simpson`, `D50`, or `chao1`
- `overlap_metric`: `jaccard` or `morisita_horn`
- `run_report`: render the final HTML report

## Outputs

Per-step tables/plots/AnnData under `results/`: `s1_load/`, `s2_chain_qc_filter/`,
`s3_define_clonotypes/`, `s4_clonal_expansion/`, `s5_diversity/`,
`s6_repertoire_overlap/`, `s7_gene_usage_spectratype/`, `s8_report/` (if enabled).

**Docker image:** `tronghieunguyen/bcr-scirpy:latest` (see `bcr-pipelines/scirpy/Dockerfile`)
