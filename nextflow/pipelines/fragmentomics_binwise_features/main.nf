#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { BINWISE_FEATURES } from '../fragmentomics_TF_features/modules/binwise_features/main'

workflow {
    // Samplesheet columns: SampleID, short_bam, long_bam, full_bam
    // All BAM files must already be indexed (.bai alongside each .bam).
    if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

    ch_samples = Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def norm      = row.collectEntries { k, v -> [k.trim().toLowerCase(), v?.trim()] }
            def id        = norm['sampleid']
            def short_bam = norm['short_bam']
            def long_bam  = norm['long_bam']
            def full_bam  = norm['full_bam']
            tuple(
                id,
                file(short_bam), file("${short_bam}.bai"),
                file(long_bam),  file("${long_bam}.bai"),
                file(full_bam),  file("${full_bam}.bai"),
            )
        }

    BINWISE_FEATURES(ch_samples)
}
