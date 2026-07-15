include { CELL_CYCLE_SCORING_S6 } from '../modules/cell_cycle_scoring_s6/main'

workflow CELL_CYCLE_SCORING_S6_WF {
    take:
    ch_anndata
    mode

    main:
    CELL_CYCLE_SCORING_S6(ch_anndata, mode)

    emit:
    anndata = CELL_CYCLE_SCORING_S6.out.anndata
    summary = CELL_CYCLE_SCORING_S6.out.summary
    plots   = CELL_CYCLE_SCORING_S6.out.plots
}
