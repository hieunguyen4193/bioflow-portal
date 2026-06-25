#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { BINWISE_FEATURES } from '../fragmentomics_TF_features/modules/binwise_features/main'

if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"
// Samplesheet columns: SampleID, short_bam, long_bam, full_bam
// All BAM files must already be indexed (.bai alongside each .bam).

workflow {
    ch_samples = Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            tuple(
                row.SampleID,
                file(row.short_bam), file("${row.short_bam}.bai"),
                file(row.long_bam),  file("${row.long_bam}.bai"),
                file(row.full_bam),  file("${row.full_bam}.bai"),
            )
        }

    BINWISE_FEATURES(ch_samples)
}
