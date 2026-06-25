#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { BULK_FEATURES          } from '../fragmentomics_TF_features/modules/bulk_features/main'
include { BULK_FEATURES_FROM_FRAG } from '../fragmentomics_TF_features/modules/bulk_features_from_frag/main'

if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

workflow {
    ch_samples = Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row -> tuple(row.SampleID, file(row.Path)) }

    if (params.mode == "from_frag_file") {
        BULK_FEATURES_FROM_FRAG(ch_samples)
    } else {
        BULK_FEATURES(ch_samples)
    }
}
