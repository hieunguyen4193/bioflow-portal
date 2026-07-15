include { DOUBLET_DETECTION } from '../modules/doublet_detection/main'

workflow DOUBLET_DETECTION_WF {
    take:
    ch_anndata
    doublet_csv
    remove_doublet

    main:
    DOUBLET_DETECTION(ch_anndata, doublet_csv, remove_doublet)

    emit:
    anndata = DOUBLET_DETECTION.out.anndata
    summary = DOUBLET_DETECTION.out.summary
    plots   = DOUBLET_DETECTION.out.plots
}
