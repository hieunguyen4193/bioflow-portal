#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { IMMUNARCH_PIPELINE } from './workflows/immunarch_pipeline'

// ── Input ────────────────────────────────────────────────────────────────
// samplesheet.csv columns: SampleID, contig_annotations, subject
//   contig_annotations  = cellranger vdj outs/filtered_contig_annotations.csv
//   subject (optional)  = passthrough grouping label; defaults to SampleID.
// Like scirpy, immunarch trusts Cell Ranger's own V(D)J gene calls
// (no independent IgBLAST reannotation).
params.samplesheet = null

// ── S2: Repertoire exploration ──────────────────────────────────────────────
params.explore_method = "volume"   // volume | len | count | samples

// ── S3: Clonality ────────────────────────────────────────────────────────────
params.clonality_method = "clonal.prop"   // homeo | clonal.prop | top | rare

// ── S4: Diversity ────────────────────────────────────────────────────────────
params.diversity_method = "chao1"   // chao1 | hill | div | gini.simp | inv.simp | gini | raref

// ── S5: Gene usage ───────────────────────────────────────────────────────────
params.gene_reference = "hs.ighv"   // immunarch built-in IG gene reference (V/J, heavy/kappa/lambda)
params.gene_col       = "V.name"    // fallback manual column if gene_reference isn't recognized

// ── S6: Clonal tracking (optional) ──────────────────────────────────────────
params.run_tracking      = "false"
params.top_n_clonotypes  = 10

// ── S7: Repertoire overlap ───────────────────────────────────────────────────
params.overlap_method = "jaccard"   // public | jaccard | morisita | tversky | cosine

// ── S8: K-mer analysis (optional) ───────────────────────────────────────────
params.run_kmer  = "false"
params.kmer_k    = 5
params.kmer_head = 10

// ── S9: HTML report ───────────────────────────────────────────────────────────
params.run_report = "true"

params.outdir = "${launchDir}/results"

workflow {
    if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

    IMMUNARCH_PIPELINE(file(params.samplesheet), params)
}
