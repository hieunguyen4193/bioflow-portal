#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { ENRICH_FILTER_BED  } from '../fragmentomics_TF_features/modules/enrich_filter_bed/main'
include { ENRICH_FILTER_FLEN } from '../fragmentomics_TF_features/modules/enrich_filter_flen/main'
include { ENRICH_FILTER_ND   } from '../fragmentomics_TF_features/modules/enrich_filter_nd/main'

workflow {
    // Samplesheet columns depend on mode:
    //   filter_bed  -> SampleID, Path (BAM), BED (BED file path)
    //   filter_flen -> SampleID, Path (BAM)
    //   filter_nd   -> SampleID, Path (FLEN_EM_ND.tsv)
    if (!params.samplesheet) error "Provide --samplesheet <path/to/samplesheet.csv>"

    if (params.mode == "filter_bed") {
        ch = Channel
            .fromPath(params.samplesheet)
            .splitCsv(header: true)
            .map { row ->
                def id   = row.find { it.key.toLowerCase() == 'sampleid' }?.value
                def path = row.find { it.key.toLowerCase() == 'path' }?.value
                def bed  = row.find { it.key.toLowerCase() == 'bed' }?.value
                tuple(id, file(path), file(bed))
            }
        ENRICH_FILTER_BED(ch)

    } else if (params.mode == "filter_nd") {
        ch = Channel
            .fromPath(params.samplesheet)
            .splitCsv(header: true)
            .map { row ->
                def id   = row.find { it.key.toLowerCase() == 'sampleid' }?.value
                def path = row.find { it.key.toLowerCase() == 'path' }?.value
                tuple(id, file(path))
            }
        ENRICH_FILTER_ND(ch)

    } else {
        // default: filter_flen
        ch = Channel
            .fromPath(params.samplesheet)
            .splitCsv(header: true)
            .map { row ->
                def id   = row.find { it.key.toLowerCase() == 'sampleid' }?.value
                def path = row.find { it.key.toLowerCase() == 'path' }?.value
                tuple(id, file(path))
            }
        ENRICH_FILTER_FLEN(ch)
    }
}
