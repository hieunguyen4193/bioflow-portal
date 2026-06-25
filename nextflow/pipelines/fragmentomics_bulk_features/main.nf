#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { BULK_FEATURES          } from '../fragmentomics_TF_features/modules/bulk_features/main'
include { BULK_FEATURES_FROM_FRAG } from '../fragmentomics_TF_features/modules/bulk_features_from_frag/main'

workflow {
    if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

    ch_samples = Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def id   = row.find { it.key.toLowerCase() == 'sampleid' }?.value
            def path = row.find { it.key.toLowerCase() == 'path' }?.value
            tuple(id, file(path))
        }

    if (params.mode == "from_frag_file") {
        BULK_FEATURES_FROM_FRAG(ch_samples)
    } else {
        BULK_FEATURES(ch_samples)
    }
}
