#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { BINWISE_FEATURES } from '../fragmentomics_TF_features/modules/binwise_features/main'
include { SPLIT_BAM        } from './modules/split_bam/main'

// Samplesheet modes:
//   Full mode  — columns: SampleID, short_bam, long_bam, full_bam (all pre-split)
//   Auto-split — columns: SampleID, full_bam only (short/long derived at runtime, cutoff = params.split_cutoff)

workflow {
    if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

    ch_rows = Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row -> row.collectEntries { k, v -> [k.trim().toLowerCase(), v?.trim()] } }

    ch_has_split = ch_rows.branch {
        presplit: it['short_bam'] && it['long_bam']
        autosplit: true
    }

    // Pre-split path: short_bam, long_bam, full_bam all provided
    ch_presplit = ch_has_split.presplit.map { norm ->
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

    // Auto-split path: only full_bam provided — run SPLIT_BAM first
    ch_autosplit_input = ch_has_split.autosplit.map { norm ->
        def id       = norm['sampleid']
        def full_bam = norm['full_bam']
        tuple(id, file(full_bam), file("${full_bam}.bai"))
    }

    SPLIT_BAM(ch_autosplit_input)

    ch_all = ch_presplit.mix(SPLIT_BAM.out.split_bams)
    BINWISE_FEATURES(ch_all)
}
