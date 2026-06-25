#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { FRAGMENTOMICS } from './workflows/fragmentomics'

// Validate required params
if (!params.samplesheet) {
    error "Please provide a samplesheet with --samplesheet <path/to/samplesheet.csv>"
}
if (!params.projectdir) {
    error "Please provide the Fragmentomics source directory with --projectdir <path>"
}

workflow {
    // Read sample sheet: expects header SampleID,Path
    ch_samples = Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def sampleID = row.SampleID ?: row.sampleID ?: row.sample_id
            def path     = row.Path ?: row.path ?: row.BAM ?: row.CRAM
            if (!sampleID || !path) {
                error "Samplesheet must have SampleID and Path columns. Got: ${row}"
            }
            tuple(sampleID, file(path))
        }

    FRAGMENTOMICS(ch_samples)
}
