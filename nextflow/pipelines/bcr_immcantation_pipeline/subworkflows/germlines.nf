include { CREATE_GERMLINES } from '../modules/create_germlines/main'

workflow GERMLINES {
    take:
    ch_clone_pass   // tuple: [subject, clone_pass_tsv]
    species

    main:
    CREATE_GERMLINES(ch_clone_pass, species)

    emit:
    germ_pass = CREATE_GERMLINES.out.germ_pass   // tuple: [subject, germ_pass_tsv]
}
