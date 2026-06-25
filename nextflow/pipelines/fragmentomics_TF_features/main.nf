#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { FRAGMENTOMICS } from './workflows/fragmentomics'

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

    FRAGMENTOMICS(ch_samples)
}
