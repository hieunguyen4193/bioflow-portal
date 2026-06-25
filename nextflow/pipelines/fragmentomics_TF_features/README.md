# Fragmentomics — TF and Enrichment Features

Generates a suite of cell-free DNA fragmentomics features from WGS BAM/CRAM files. Wraps the `Fragmentomics_TF_and_enrich_features` pipeline into a Nextflow DSL2 workflow.

## Input

A **CSV samplesheet** with two columns:

```
SampleID,Path
SAMPLE_01,/path/to/SAMPLE_01.sorted.bam
SAMPLE_02,/path/to/SAMPLE_02.sorted.bam
```

For CRAM input set `--input_type cram` — an extra conversion step runs first.

## Pipeline steps

| Step | Description | Optional |
|------|-------------|----------|
| **Step 0** | CRAM → BAM conversion (`samtools view`) | Yes (only for CRAM input) |
| **Step 01** | Preprocess BAM: sort/index, split by fragment size, convert to BEDPE, genome coverage | No |
| **Step 02** | Chromosome-level fragment features (std, avg, Shannon entropy) | Yes |
| **Step 03** | CNA features for TFBS coverage (bin 100 kb + 1 Mb) | Yes |
| **Step 04** | Coverage profile features across TFBS sites | Yes (requires step 03) |
| **Step 05** | WPS / IFS / FDI features across TFBS sites | Yes (requires step 02) |
| **Step 06** | RFE (Relative Fragment End) features across TFBS sites | Yes |

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `samplesheet` | — | Path to input CSV (required) |
| `input_type` | `bam` | `bam` or `cram` |
| `projectdir` | — | Path to the `Fragmentomics_TF_and_enrich_features` source directory |
| `ref_genome` | `/mnt/NFS_190T/.../hg19.fa` | Reference genome FASTA (required for CRAM) |
| `tfbs_dir` | `/mnt/NFS_190T/.../TFBS` | Directory containing TFBS `.bed` files |
| `nucleosome_ref` | `/mnt/NFS_190T/.../rpr_map_EXP0779.bed` | Nucleosome reference BED |
| `nthreads` | `4` | samtools threads per sample |
| `short_lower/upper` | `50/150` | Short fragment length range (bp) |
| `long_lower/upper` | `151/350` | Long fragment length range (bp) |
| `min_flen/max_flen` | `50/350` | Fragment length filter for BEDPE conversion |
| `markdup` | `false` | Mark duplicates with Picard before processing |

## Outputs

```
results/
  step01_process_bam/<SampleID>/      sorted BAM, splitChroms, frag bed.gz, genomeCov
  step02_chromosome_features/         *_std_avg_shannon.tsv per sample
  step03_cna_features/<SampleID>/     *.bin100kb.bed, *.bin1M.bed
  step04_coverage_profile/<SampleID>/ coverage profile feature files per TFBS
  step05_wps_ifs_fdi/<SampleID>/      WPS/IFS/FDI feature files per TFBS
  step06_rfe_features/<SampleID>/     RFE feature files per TFBS
```

## Docker image

`tronghieunguyen/wgs-fragmentomics-features:latest`

The image must have access to the resource directories. Configured via `docker.runOptions` in `nextflow.config` — adjust the volume mounts for your server.

## Notes

- Each sample is processed independently; Nextflow parallelises across samples automatically.
- Steps 04 and 05 depend on steps 03 and 02 respectively; disabling an upstream step also skips the downstream one.
- The pipeline stores all intermediate files in `results/` under the job output directory.
