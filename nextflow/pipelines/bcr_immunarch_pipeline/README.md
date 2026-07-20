# BCR repertoire analysis — immunarch

Runs [immunarch](https://immunarch.com/) on single-cell BCR data from 10x
Genomics `cellranger vdj`. immunarch is the fastest/most exploratory of the
four BCR pipelines in this portal — quick statistical summaries rather than
sequence-level reannotation. Like scirpy, it trusts Cell Ranger's own V(D)J
gene calls.

## Input

`samplesheet.csv` columns:

| Column | Description |
|---|---|
| `SampleID` | Unique sample identifier |
| `contig_annotations` | `outs/filtered_contig_annotations.csv` from `cellranger vdj` |
| `subject` | *(optional)* passthrough grouping label written into immunarch's sample metadata; defaults to `SampleID` when blank |

## Steps

| Step | Description | Optional |
|------|-------------|----------|
| S1 | Load all samples via `repLoad()` into one immunarch `immdata` object | No |
| S2 | Repertoire exploration (`repExplore`: clone volume/length/count) | No |
| S3 | Clonality (`repClonality`: homeostasis / top / rare / clonal proportion) | No |
| S4 | Diversity (`repDiversity`: chao1, hill, gini-simpson, etc.) | No |
| S5 | V/J gene usage (`geneUsage`, falls back to manual counts if the gene reference isn't recognized) | No |
| S6 | Clonal tracking of top N clonotypes across samples (`trackClonotypes`) | Yes (off by default) |
| S7 | Pairwise repertoire overlap (`repOverlap`; auto no-ops for a single sample) | No |
| S8 | CDR3 k-mer frequency analysis (`getKmers`) | Yes (off by default) |
| S9 | HTML report (sample summary, exploration, clonality, diversity, gene usage, overlap) | Yes |

Clonal tracking (S6) and k-mer analysis (S8) are independent side-outputs and
are not embedded in the S9 report.

## Key parameters

- `explore_method`: `volume` \| `len` \| `count` \| `samples`
- `clonality_method`: `homeo` \| `clonal.prop` \| `top` \| `rare`
- `diversity_method`: `chao1` \| `hill` \| `div` \| `gini.simp` \| `inv.simp` \| `gini` \| `raref`
- `gene_reference`: immunarch built-in IG gene reference, e.g. `hs.ighv` (heavy), `hs.igkv`/`hs.iglv` (light)
- `overlap_method`: `public` \| `jaccard` \| `morisita` \| `tversky` \| `cosine`
- `run_tracking` / `top_n_clonotypes`, `run_kmer` / `kmer_k` / `kmer_head`: optional side-analyses
- `run_report`: render the final HTML report

## Outputs

Per-step tables/plots under `results/`: `s1_load/`, `s2_explore/`,
`s3_clonality/`, `s4_diversity/`, `s5_gene_usage/`, `s6_clonal_tracking/`
(if enabled), `s7_overlap/`, `s8_kmer_analysis/` (if enabled), `s9_report/`
(if enabled).

**Docker image:** `tronghieunguyen/bcr-immunarch:latest` (see `bcr-pipelines/immunarch/Dockerfile`)
