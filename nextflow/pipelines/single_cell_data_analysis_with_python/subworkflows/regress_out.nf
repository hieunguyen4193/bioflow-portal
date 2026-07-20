include { REGRESS_OUT } from '../modules/regress_out/main'

workflow REGRESS_OUT_WF {
    take:
    ch_anndata
    features_to_regressOut
    regressOut_mode

    main:
    REGRESS_OUT(ch_anndata, features_to_regressOut, regressOut_mode)

    emit:
    anndata = REGRESS_OUT.out.anndata
}
