#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { SCIRPY_PIPELINE } from './workflows/scirpy_pipeline'

// ── Input ────────────────────────────────────────────────────────────────
// samplesheet.csv columns: SampleID, contig_annotations, subject
//   contig_annotations  = cellranger vdj outs/filtered_contig_annotations.csv
//   subject (optional)  = passthrough grouping label carried into adata.obs;
//                         defaults to SampleID when left blank.
// Unlike Immcantation, scirpy trusts Cell Ranger's own V(D)J gene calls
// (no independent IgBLAST reannotation), and clonotyping runs across the
// whole concatenated dataset rather than per subject.
params.samplesheet = null

// ── S2: Chain QC filtering ──────────────────────────────────────────────────
params.remove_multichain = true
params.require_paired    = true

// ── S3: Clonotype definition ────────────────────────────────────────────────
params.clustering_mode = "clonotype_clusters"   // clonotypes | clonotype_clusters
params.sequence        = "nt"                    // nt | aa  (used when clustering_mode = clonotype_clusters)
params.metric          = "hamming"               // identity | hamming | levenshtein | alignment
params.receptor_arms   = "all"                   // all | any | VJ | VDJ
params.dual_ir         = "primary_only"          // primary_only | any | all

// ── S5: Alpha diversity ──────────────────────────────────────────────────────
params.diversity_metric = "normalized_shannon_entropy"   // normalized_shannon_entropy | gini_simpson | D50 | chao1

// ── S6: Repertoire overlap ────────────────────────────────────────────────────
params.overlap_metric = "jaccard"   // jaccard | morisita_horn

// ── S8: HTML report ────────────────────────────────────────────────────────────
params.run_report = "true"

params.outdir = "${launchDir}/results"

workflow {
    if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

    SCIRPY_PIPELINE(file(params.samplesheet), params)
}
