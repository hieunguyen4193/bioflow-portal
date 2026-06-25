include { DOWNSAMPLE } from '../modules/downsample/main'

workflow DOWNSAMPLE_WF {
    take:
    ch_seurat_rds
    downsample_type
    downsample_value

    main:
    DOWNSAMPLE(ch_seurat_rds, downsample_type, downsample_value)

    emit:
    seurat_rds = DOWNSAMPLE.out.seurat_rds
}
