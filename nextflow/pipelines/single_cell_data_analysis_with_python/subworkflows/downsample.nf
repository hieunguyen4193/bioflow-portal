include { DOWNSAMPLE } from '../modules/downsample/main'

workflow DOWNSAMPLE_WF {
    take:
    ch_anndata
    downsample_type
    downsample_value

    main:
    DOWNSAMPLE(ch_anndata, downsample_type, downsample_value)

    emit:
    anndata = DOWNSAMPLE.out.anndata
}
