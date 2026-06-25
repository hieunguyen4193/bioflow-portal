#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { ENRICH_FILTER_BED  } from '../fragmentomics_TF_features/modules/enrich_filter_bed/main'
include { ENRICH_FILTER_FLEN } from '../fragmentomics_TF_features/modules/enrich_filter_flen/main'
include { ENRICH_FILTER_ND   } from '../fragmentomics_TF_features/modules/enrich_filter_nd/main'

if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

// Samplesheet columns depend on mode:
//   filter_bed  -> SampleID, Path (BAM), BED (BED file path)
//   filter_flen -> SampleID, Path (BAM)
//   filter_nd   -> SampleID, Path (FLEN_EM_ND.tsv)

workflow {
    if (params.mode == "filter_bed") {
        ch = Channel
            .fromPath(params.samplesheet)
            .splitCsv(header: true)
            .map { row -> tuple(row.SampleID, file(row.Path), file(row.BED)) }
        ENRICH_FILTER_BED(ch)

    } else if (params.mode == "filter_nd") {
        ch = Channel
            .fromPath(params.samplesheet)
            .splitCsv(header: true)
            .map { row -> tuple(row.SampleID, file(row.Path)) }
        ENRICH_FILTER_ND(ch)

    } else {
        // default: filter_flen
        ch = Channel
            .fromPath(params.samplesheet)
            .splitCsv(header: true)
            .map { row -> tuple(row.SampleID, file(row.Path)) }
        ENRICH_FILTER_FLEN(ch)
    }
}
