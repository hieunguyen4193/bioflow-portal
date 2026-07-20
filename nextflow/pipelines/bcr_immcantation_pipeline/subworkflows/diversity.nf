include { CLONAL_DIVERSITY } from '../modules/clonal_diversity/main'

workflow DIVERSITY {
    take:
    ch_shm_table   // tuple: [subject, shm_tsv]
    nboot

    main:
    CLONAL_DIVERSITY(ch_shm_table, nboot)

    emit:
    abundance_table = CLONAL_DIVERSITY.out.abundance_table   // tuple: [subject, abundance_tsv]
    diversity_table = CLONAL_DIVERSITY.out.diversity_table   // tuple: [subject, diversity_tsv]
}
