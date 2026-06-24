include { UMAP_CLUSTERING } from '../modules/umap_clustering/main'

workflow UMAP_CLUSTERING_WF {
    take:
    ch_seurat_rds
    use_sctransform
    num_PCA
    num_PC_used_in_UMAP
    num_PC_used_in_Clustering
    cluster_resolution
    vars_to_regress
    remove_genes

    main:
    UMAP_CLUSTERING(
        ch_seurat_rds,
        use_sctransform,
        num_PCA,
        num_PC_used_in_UMAP,
        num_PC_used_in_Clustering,
        cluster_resolution,
        vars_to_regress,
        remove_genes
    )

    emit:
    seurat_rds = UMAP_CLUSTERING.out.seurat_rds
}
