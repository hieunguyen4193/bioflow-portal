# Fragmentomics — Enrichment Filters

Filters BAM files or fragment tables to enrich for specific sub-populations of fragments. Three independent filter modes are available.

## Modes

| Mode | Input | Description |
|------|-------|-------------|
| `filter_flen` | BAM | Splits BAM into short (≤ 150 bp), long (151–350 bp), and full (50–350 bp) sub-BAMs |
| `filter_bed` | BAM + BED | Keeps only reads overlapping a supplied BED file (e.g., TFBS, enhancers) |
| `filter_nd` | FLEN_EM_ND.tsv | Filters fragment rows by nucleosome-distance range (`nd_min`–`nd_max`) |

## Samplesheet formats

### `filter_flen` and `filter_nd`

```csv
SampleID,Path
sample01,/path/to/file
```

### `filter_bed`

```csv
SampleID,Path,BED
sample01,/path/to/sample01.bam,/path/to/regions.bed
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `mode` | `filter_flen` | Filter type: `filter_flen`, `filter_bed`, or `filter_nd` |
| `bed_file` | — | Server-side BED path (used only in `filter_bed` mode if not in samplesheet) |
| `nd_min` | 0 | Minimum nucleosome distance (for `filter_nd`) |
| `nd_max` | 50 | Maximum nucleosome distance (for `filter_nd`) |
