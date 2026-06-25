include { CREATE_SEURAT } from '../modules/create_seurat/main'

workflow QC_AND_SEURAT {
    take:
    ch_input        // tuple: [sample, barcodes, features, matrix]
    min_cells
    min_features
    max_features
    max_mt_pct
    remove_tcr_genes

    main:
    CREATE_SEURAT(
        ch_input,
        min_cells,
        min_features,
        max_features,
        max_mt_pct,
        remove_tcr_genes
    )

    emit:
    seurat_rds = CREATE_SEURAT.out.seurat_rds
    plots      = CREATE_SEURAT.out.plots
    qc_table   = CREATE_SEURAT.out.qc_table
}
