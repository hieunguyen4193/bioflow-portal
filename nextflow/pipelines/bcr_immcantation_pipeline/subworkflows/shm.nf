include { SHM_ANALYSIS } from '../modules/shm_analysis/main'

workflow SHM {
    take:
    ch_germ_pass   // tuple: [subject, germ_pass_tsv]

    main:
    SHM_ANALYSIS(ch_germ_pass)

    emit:
    shm_table = SHM_ANALYSIS.out.shm_table   // tuple: [subject, shm_tsv]
}
