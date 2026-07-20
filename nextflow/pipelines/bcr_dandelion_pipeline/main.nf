#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { DANDELION_PIPELINE } from './workflows/dandelion_pipeline'

// ── Input ────────────────────────────────────────────────────────────────
// samplesheet.csv columns: SampleID, contig_fasta, contig_annotations, subject
//   contig_fasta        = cellranger vdj outs/filtered_contig.fasta
//   contig_annotations  = cellranger vdj outs/filtered_contig_annotations.csv
//   subject (optional)  = groups samples for per-subject clone
//                         definition/network construction; defaults to
//                         SampleID when left blank.
// Like Immcantation, Dandelion reannotates V(D)J genes independently via
// IgBLAST rather than trusting Cell Ranger's calls.
params.samplesheet = null
params.species     = "human"   // human | mouse

// ── S2: Contig QC ────────────────────────────────────────────────────────────
params.productive_only = true

// ── S3: Clone definition ─────────────────────────────────────────────────────
params.identity_threshold = 0.85

// ── S4: Clonal network ───────────────────────────────────────────────────────
params.min_network_size = 2

// ── S5: Diversity ─────────────────────────────────────────────────────────────
params.diversity_method = "chao1"   // chao1 | shannon | simpson | gini

// ── S7: HTML report ────────────────────────────────────────────────────────────
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

    DANDELION_PIPELINE(ch_input, params)
}
