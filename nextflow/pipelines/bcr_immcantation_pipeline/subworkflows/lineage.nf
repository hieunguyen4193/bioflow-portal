include { LINEAGE_TREES } from '../modules/lineage_trees/main'

workflow LINEAGE {
    take:
    ch_germ_pass   // tuple: [subject, germ_pass_tsv]
    min_seqs

    main:
    LINEAGE_TREES(ch_germ_pass, min_seqs)

    emit:
    trees_rds = LINEAGE_TREES.out.trees_rds
    trees_pdf = LINEAGE_TREES.out.trees_pdf
}
