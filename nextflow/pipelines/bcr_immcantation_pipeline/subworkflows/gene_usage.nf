include { GENE_USAGE } from '../modules/gene_usage/main'

workflow GENE_USAGE_WF {
    take:
    ch_shm_table   // tuple: [subject, shm_tsv]

    main:
    GENE_USAGE(ch_shm_table)

    emit:
    gene_usage_tables = GENE_USAGE.out.gene_usage_tables   // tuple: [subject, v_usage_tsv, j_usage_tsv]
}
