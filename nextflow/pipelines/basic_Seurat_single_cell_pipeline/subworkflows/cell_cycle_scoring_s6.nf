include { CELL_CYCLE_SCORING_S6 } from '../modules/cell_cycle_scoring_s6/main'

workflow CELL_CYCLE_SCORING_S6_WF {
    take:
    ch_seurat_rds
    mode

    main:
    CELL_CYCLE_SCORING_S6(ch_seurat_rds, mode)

    emit:
    seurat_rds = CELL_CYCLE_SCORING_S6.out.seurat_rds
    summary    = CELL_CYCLE_SCORING_S6.out.summary
    plots      = CELL_CYCLE_SCORING_S6.out.plots
}
