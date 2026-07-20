#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { IMMCANTATION_PIPELINE } from './workflows/immcantation_pipeline'

// ── Input ────────────────────────────────────────────────────────────────
// samplesheet.csv columns: SampleID, contig_fasta, contig_annotations, subject
//   contig_fasta        = cellranger vdj outs/filtered_contig.fasta
//   contig_annotations  = cellranger vdj outs/filtered_contig_annotations.csv
//   subject (optional)  = groups samples for per-subject clonal clustering;
//                         defaults to SampleID when left blank.
params.samplesheet = null
params.species      = "human"   // human | mouse

// ── S3: Clonal distance threshold ──────────────────────────────────────────
params.auto_threshold  = "true"   // SHazaM distToNearest + findThreshold(density)
params.dist_threshold  = 0.15     // used as fallback, or as-is when auto_threshold = "false"

// ── S4: Change-O clonal clustering ─────────────────────────────────────────
params.clone_model = "ham"   // ham | aa | hh_s1f | hh_s5f
params.clone_norm  = "len"   // len | none

// ── S7: Clonal diversity ────────────────────────────────────────────────────
params.nboot = 100

// ── S9: Lineage trees (optional) ────────────────────────────────────────────
params.run_lineage      = "false"
params.lineage_min_seqs = 3

// ── S10: HTML report ─────────────────────────────────────────────────────────
params.run_report = "true"

params.outdir = "${launchDir}/results"

workflow {
    if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

    ch_input = Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true, strip: true)
        .map { row ->
            def sample_id = row.SampleID
            def subject   = (row.subject ?: "").trim()
            if (!subject) subject = sample_id
            tuple(sample_id, subject, file(row.contig_fasta), file(row.contig_annotations))
        }

    IMMCANTATION_PIPELINE(ch_input, params)
}
