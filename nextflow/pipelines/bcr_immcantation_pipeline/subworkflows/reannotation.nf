include { IGBLAST_REANNOTATION } from '../modules/igblast_reannotation/main'

workflow REANNOTATION {
    take:
    ch_input   // tuple: [sample_id, subject, contig_fasta, contig_annotations]
    species

    main:
    IGBLAST_REANNOTATION(ch_input, species)

    emit:
    db_pass = IGBLAST_REANNOTATION.out.db_pass   // tuple: [sample_id, subject, db_pass_tsv]
}
