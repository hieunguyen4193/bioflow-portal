include { FILTER_FUNCTIONAL } from '../modules/filter_functional/main'

workflow FILTERING {
    take:
    ch_db_pass   // tuple: [sample_id, subject, db_pass_tsv]

    main:
    FILTER_FUNCTIONAL(ch_db_pass)

    emit:
    functional     = FILTER_FUNCTIONAL.out.functional       // tuple: [sample_id, subject, functional_tsv]
    functional_igh = FILTER_FUNCTIONAL.out.functional_igh    // tuple: [sample_id, subject, functional_igh_tsv]
}
