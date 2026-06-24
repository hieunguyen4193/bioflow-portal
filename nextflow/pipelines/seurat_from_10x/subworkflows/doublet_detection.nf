include { DOUBLET_DETECTION } from '../modules/doublet_detection/main'

workflow DOUBLET_DETECTION_WF {
    take:
    ch_seurat_rds
    doublet_csv
    remove_doublet

    main:
    DOUBLET_DETECTION(ch_seurat_rds, doublet_csv, remove_doublet)

    emit:
    seurat_rds = DOUBLET_DETECTION.out.seurat_rds
    summary    = DOUBLET_DETECTION.out.summary
    plots      = DOUBLET_DETECTION.out.plots
}
