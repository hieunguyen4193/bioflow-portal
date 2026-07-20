include { DEFINE_CLONES } from '../modules/define_clones/main'

workflow CLUSTERING {
    take:
    ch_threshold   // tuple: [subject, combined_igh_tsv, threshold_txt]
    model
    norm

    main:
    DEFINE_CLONES(ch_threshold, model, norm)

    emit:
    clone_pass = DEFINE_CLONES.out.clone_pass   // tuple: [subject, clone_pass_tsv]
}
