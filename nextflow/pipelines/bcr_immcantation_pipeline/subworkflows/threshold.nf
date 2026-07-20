include { COMBINE_SUBJECT } from '../modules/combine_subject/main'
include { SHAZAM_THRESHOLD } from '../modules/shazam_threshold/main'

workflow THRESHOLD {
    take:
    ch_functional_igh   // tuple: [sample_id, subject, functional_igh_tsv]
    auto_threshold
    manual_threshold

    main:
    ch_grouped = ch_functional_igh
        .map { sample_id, subject, path -> tuple(subject, sample_id, path) }
        .groupTuple(by: 0)

    COMBINE_SUBJECT(ch_grouped)
    SHAZAM_THRESHOLD(COMBINE_SUBJECT.out.combined, auto_threshold, manual_threshold)

    emit:
    threshold = SHAZAM_THRESHOLD.out.threshold   // tuple: [subject, combined_igh_tsv, threshold_txt]
}
