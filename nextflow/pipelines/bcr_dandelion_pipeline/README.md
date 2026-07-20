# BCR repertoire analysis — Dandelion

Runs [sc-dandelion](https://sc-dandelion.readthedocs.io/) on single-cell BCR
data from 10x Genomics `cellranger vdj`. Like Immcantation, Dandelion
independently reannotates V(D)J genes via IgBLAST rather than trusting Cell
Ranger's calls. Its most distinctive feature relative to the other three
pipelines in this portal is clone definition via a **clonal similarity
network** (a graph per subject, rather than nearest-neighbor clustering,
identity-based clonotypes, or simple exact grouping).

## Input

`samplesheet.csv` columns:

| Column | Description |
|---|---|
| `SampleID` | Unique sample identifier |
| `contig_fasta` | `outs/filtered_contig.fasta` from `cellranger vdj` |
| `contig_annotations` | `outs/filtered_contig_annotations.csv` from `cellranger vdj` |
| `subject` | *(optional)* groups samples from the same individual for clone definition/network construction. Defaults to `SampleID` when blank. |

## Steps

| Step | Description | Optional |
|------|-------------|----------|
| S1 | Format contig IDs + IgBLAST V(D)J reannotation (`ddl.pp.format_fastas`, `ddl.pp.reannotate_genes`) | No |
| S2 | Contig QC — ambiguous/chimeric filtering, optional productive-only filter (`ddl.pp.check_contigs`) | No |
| S3 | Clone definition per subject (`ddl.tl.find_clones`) | No |
| S4 | Clonal similarity network construction + plot (`ddl.tl.generate_network`) | No |
| S5 | Clone size distribution + diversity (`ddl.tl.clone_size`, `ddl.tl.clone_diversity`) | No |
| S6 | V gene usage (heavy + light) | No |
| S7 | Per-subject HTML report | Yes |

## Key parameters

- `species`: `human` or `mouse`
- `productive_only`: keep only productive contigs during QC
- `identity_threshold`: CDR3 sequence identity threshold for clone definition (0–1)
- `min_network_size`: minimum clone size included in the network plot
- `diversity_method`: `chao1`, `shannon`, `simpson`, or `gini`
- `run_report`: render the final per-subject HTML report

## Outputs

Per-sample/per-subject tables and plots under `results/`: `s1_format_reannotate/`,
`s2_contig_qc/`, `s2b_combined_by_subject/`, `s3_find_clones/`,
`s4_clonal_network/`, `s5_clone_size_diversity/`, `s6_gene_usage/`,
`s7_report/` (if enabled).

**Docker image:** `tronghieunguyen/bcr-dandelion:latest` (`bcr-pipelines/dandelion/Dockerfile`, based on `sctdandelion/dandelion`)

## A note on API stability

Dandelion's public API has less universal documentation coverage than
scirpy/Immcantation/immunarch, and this pipeline was written from the
official tutorials without the ability to execute it end to end in this
environment. Several steps (especially `generate_network`'s graph/layout
access and `clone_diversity`'s method names) are wrapped defensively so a
version mismatch degrades to a placeholder output instead of crashing the
run — check the process logs and, if needed, the
[official tutorial](https://sc-dandelion.readthedocs.io/) against your
installed Dandelion version.
