# Fragmentomics — Bulk Features

Computes bulk fragmentomics features from cfDNA WGS data.

## Modes

| Mode | Input samplesheet | Description |
|------|------------------|-------------|
| `from_bam` | `SampleID, Path` (BAM) | Derives fragment file from BAM, then computes EM + nucleosome distance features, and finally bulk features |
| `from_frag_file` | `SampleID, Path` (FLEN_EM_ND.tsv) | Skips fragment derivation; uses pre-computed FLEN/EM/ND table directly |

## Samplesheet format

```csv
SampleID,Path
sample01,/path/to/sample01.bam
sample02,/path/to/sample02.bam
```

## Key outputs

- `*_bulk_features/` — directory of per-sample bulk feature matrices
- `*_FLEN_EM_ND.tsv` — fragment length / EM / nucleosome-distance table (produced in `from_bam` mode)

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `mode` | `from_bam` | `from_bam` or `from_frag_file` |
| `ref_genome` | hg19.fa NFS path | Reference genome FASTA |
| `nucleosome_ref` | Budhraja STM2023 BED | Nucleosome reference positions |
| `min_flen` | 50 | Minimum fragment length |
| `max_flen` | 350 | Maximum fragment length |
