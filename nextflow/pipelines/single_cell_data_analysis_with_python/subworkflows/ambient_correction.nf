include { AMBIENT_DECONTAMINATION } from '../modules/ambient_decontamination/main'

workflow AMBIENT_CORRECTION {
    take:
    ch_anndata   // tuple: [sample, h5ad_path]
    method

    main:
    AMBIENT_DECONTAMINATION(ch_anndata, method)

    emit:
    anndata = AMBIENT_DECONTAMINATION.out.anndata
    plots   = AMBIENT_DECONTAMINATION.out.plots
}
