# Fragmentomics — Binwise Features

Computes per-genomic-bin read counts across short-fragment, long-fragment, and full BAM files using an R script.

## Samplesheet format

```csv
SampleID,short_bam,long_bam,full_bam
sample01,/path/to/sample01_short.bam,/path/to/sample01_long.bam,/path/to/sample01_full.bam
```

Each BAM must already be indexed — a `.bai` file is expected alongside each path.

## Key outputs

- `*_binwise_features/` — per-sample directory containing bin-level count matrices

## Notes

- Short BAM: fragments ≤ 150 bp
- Long BAM: fragments 151–350 bp
- Full BAM: all fragments 50–350 bp

These are typically the outputs of **Step 01 (Preprocess BAM)** from the Fragmentomics TF Features pipeline.
