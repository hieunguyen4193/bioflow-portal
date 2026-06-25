#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { PROCESS_BAM            } from '../fragmentomics_TF_features/modules/process_bam/main'
include { BULK_FEATURES          } from '../fragmentomics_TF_features/modules/bulk_features/main'
include { BULK_FEATURES_FROM_FRAG } from '../fragmentomics_TF_features/modules/bulk_features_from_frag/main'

// Samplesheet columns: SampleID, Path
//   from_bam:       Path = BAM file  → runs step01 to extract fragment file, then bulk features
//   from_frag_file: Path = pre-computed FLEN_EM_ND.tsv

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
        // from_bam: first extract the fragment file, then compute bulk features
        PROCESS_BAM(ch_samples)
        BULK_FEATURES(PROCESS_BAM.out.frag.map { id, frag, tbi -> tuple(id, frag) })
    }
}
