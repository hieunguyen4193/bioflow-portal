include { REGRESS_OUT } from '../modules/regress_out/main'

workflow REGRESS_OUT_WF {
    take:
    ch_seurat_rds
    features_to_regressOut
    regressOut_mode

    main:
    REGRESS_OUT(ch_seurat_rds, features_to_regressOut, regressOut_mode)

    emit:
    seurat_rds = REGRESS_OUT.out.seurat_rds
}
