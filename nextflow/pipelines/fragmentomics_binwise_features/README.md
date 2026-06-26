# Fragmentomics — Binwise Features

Computes per-genomic-bin read counts across short-fragment, long-fragment, and full BAM files using an R script.

## Samplesheet formats

### Mode 1 — pre-split BAMs (short, long, full already available)

```csv
SampleID,short_bam,long_bam,full_bam
sample01,/path/to/sample01_short.bam,/path/to/sample01_long.bam,/path/to/sample01_full.bam
```

When `short_bam` and `long_bam` are present the pipeline uses them directly without splitting.

### Mode 2 — auto-split from a single full BAM

```csv
SampleID,full_bam
sample01,/path/to/sample01.bam
```

`path` is also accepted as a column name alias for `full_bam` (same format as the TF features pipeline):

```csv
SampleID,Path
sample01,/path/to/sample01.bam
```

When only the full BAM is supplied the pipeline splits it automatically at `split_cutoff` bp (default **150 bp**):
- short BAM: insert size ≤ 150 bp
- long BAM: insert size > 150 bp

Each BAM must already be indexed — a `.bai` file is expected alongside each path.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `split_cutoff` | `150` | Fragment length cutoff (bp) for auto-splitting (short ≤ cutoff, long > cutoff) |
| `outdir` | `results` | Output directory |

## Outputs

```
results/
  split_bam/<SampleID>/        short.bam, long.bam (auto-split mode only)
  binwise_features/<SampleID>/ per-bin count matrices
```

## Notes

- Short BAM: fragments ≤ 150 bp
- Long BAM: fragments > 150 bp
- Full BAM: all fragments (input as-is)

Pre-split BAMs are typically the outputs of **Step 01 (Preprocess BAM)** from the Fragmentomics TF Features pipeline.
