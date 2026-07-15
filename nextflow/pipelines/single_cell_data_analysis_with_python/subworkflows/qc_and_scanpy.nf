include { CREATE_ANNDATA } from '../modules/create_anndata/main'

workflow QC_AND_SCANPY {
    take:
    ch_input        // tuple: [sample, barcodes, features, matrix]
    min_cells
    min_features
    max_features
    max_mt_pct
    remove_tcr_genes

    main:
    CREATE_ANNDATA(
        ch_input,
        min_cells,
        min_features,
        max_features,
        max_mt_pct,
        remove_tcr_genes
    )

    emit:
    anndata  = CREATE_ANNDATA.out.anndata
    plots    = CREATE_ANNDATA.out.plots
    qc_table = CREATE_ANNDATA.out.qc_table
}
