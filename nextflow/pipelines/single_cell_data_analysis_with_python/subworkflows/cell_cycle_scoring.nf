include { CELL_CYCLE_SCORING } from '../modules/cell_cycle_scoring/main'

workflow CELL_CYCLE_SCORING_WF {
    take:
    ch_anndata
    use_sctransform
    vars_to_regress

    main:
    CELL_CYCLE_SCORING(ch_anndata, use_sctransform, vars_to_regress)

    emit:
    anndata = CELL_CYCLE_SCORING.out.anndata
    summary = CELL_CYCLE_SCORING.out.summary
    plots   = CELL_CYCLE_SCORING.out.plots
}
