include { AMBIENT_DECONTAMINATION } from '../modules/ambient_decontamination/main'

workflow AMBIENT_CORRECTION {
    take:
    ch_seurat_rds   // tuple: [sample, rds_path]
    method

    main:
    AMBIENT_DECONTAMINATION(ch_seurat_rds, method)

    emit:
    seurat_rds = AMBIENT_DECONTAMINATION.out.seurat_rds
    plots      = AMBIENT_DECONTAMINATION.out.plots
}
