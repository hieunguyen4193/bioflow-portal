# BCR repertoire analysis — Immcantation

Runs the [Immcantation](https://immcantation.readthedocs.io/) framework (IgBLAST,
Change-O, SHazaM, Alakazam, dowser) on single-cell BCR data from 10x Genomics
`cellranger vdj`.

## Input

`samplesheet.csv` columns:

| Column | Description |
|---|---|
| `SampleID` | Unique sample identifier |
| `contig_fasta` | `outs/filtered_contig.fasta` from `cellranger vdj` |
| `contig_annotations` | `outs/filtered_contig_annotations.csv` from `cellranger vdj` |
| `subject` | *(optional)* groups samples from the same individual for clonal clustering/diversity/lineage analysis. Defaults to `SampleID` when blank. |

## Steps

| Step | Tool | Description | Optional |
|------|------|-------------|----------|
| S1 | IgBLAST (`AssignGenes.py`, `MakeDb.py`) | V(D)J reannotation, merged with 10x contig annotations into an AIRR rearrangement table | No |
| S2 | Change-O (`ParseDb.py`) | Keep productive/functional sequences; split by locus (IGH feeds clustering) | No |
| S3 | SHazaM (`distToNearest`, `findThreshold`) | Per-subject clonal distance threshold — auto (density method) or manual | Mode switch |
| S4 | Change-O (`DefineClones.py`) | Per-subject clonal clustering of heavy chains | No |
| S5 | Change-O (`CreateGermlines.py`) | D-masked germline reconstruction per clone | No |
| S6 | SHazaM (`observedMutations`) | Somatic hypermutation frequency (replacement/silent, CDR/FWR) | No |
| S7 | Alakazam (`countClones`, `alphaDiversity`) | Clonal abundance + Hill diversity curve (D0–D4) | No |
| S8 | Alakazam (`countGenes`) | V/J gene usage | No |
| S9 | dowser (`getTrees`, maximum parsimony) | Per-clone lineage trees (clones with ≥ `lineage_min_seqs` sequences) | Yes (off by default) |
| S10 | rmarkdown | Per-subject HTML report | Yes |

## Key parameters

- `species`: `human` or `mouse` — selects the IMGT germline/IgBLAST reference set baked into the container
- `auto_threshold` (`true`/`false`) / `dist_threshold`: clonal distance threshold mode + fallback value
- `clone_model` / `clone_norm`: Change-O distance model (`ham`, `aa`, `hh_s1f`, `hh_s5f`) and normalization (`len`, `none`)
- `nboot`: bootstrap replicates for the diversity curve
- `run_lineage`, `lineage_min_seqs`: enable lineage trees + minimum clone size to build one
- `run_report`: render the per-subject HTML report

## Outputs

Per-subject tables and plots under `results/`: `s1_igblast/`, `s2_filter_functional/`,
`s2b_combined_by_subject/`, `s3_shazam_threshold/`, `s4_define_clones/`,
`s5_create_germlines/`, `s6_shm_analysis/`, `s7_clonal_diversity/`, `s8_gene_usage/`,
`s9_lineage_trees/` (if enabled), `s10_report/` (if enabled).

**Docker image:** `tronghieunguyen/bcr-immcantation:latest` (see `bcr-pipelines/immcantation/Dockerfile`)
