include { FILTER_CELLS } from '../modules/filter_cells/main'

workflow FILTER_CELLS_WF {
    take:
    ch_anndata
    nFeatureRNA_floor
    nFeatureRNA_ceiling
    nCountRNA_floor
    nCountRNA_ceiling
    pct_mito_floor
    pct_mito_ceiling
    pct_ribo_floor
    pct_ribo_ceiling
    ambientRNA_thres
    log10GenesPerUMI_thres

    main:
    FILTER_CELLS(
        ch_anndata,
        nFeatureRNA_floor,
        nFeatureRNA_ceiling,
        nCountRNA_floor,
        nCountRNA_ceiling,
        pct_mito_floor,
        pct_mito_ceiling,
        pct_ribo_floor,
        pct_ribo_ceiling,
        ambientRNA_thres,
        log10GenesPerUMI_thres
    )

    emit:
    anndata  = FILTER_CELLS.out.anndata
    qc_table = FILTER_CELLS.out.qc_table
    plots    = FILTER_CELLS.out.plots
}
