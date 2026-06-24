#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.barcodes     = null
params.features     = null
params.matrix       = null
params.sample_name  = "sample"
params.min_cells    = 3
params.min_features = 200
params.max_features = 5000
params.max_mt_pct   = 20
params.outdir       = "results"

process CREATE_SEURAT {
    tag "${params.sample_name}"
    publishDir params.outdir, mode: "copy"

    input:
    path barcodes
    path features
    path matrix

    output:
    path "*.rds",        emit: seurat_obj
    path "*.png",        emit: plots
    path "qc_stats.csv", emit: qc_table

    script:
    """
    cat > run_seurat.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(ggplot2)
  library(Matrix)
  library(optparse)
})

option_list <- list(
  make_option("--barcodes",     type = "character"),
  make_option("--features",     type = "character"),
  make_option("--matrix",       type = "character"),
  make_option("--sample",       type = "character", default = "sample"),
  make_option("--min_cells",    type = "integer",   default = 3L),
  make_option("--min_features", type = "integer",   default = 200L),
  make_option("--max_features", type = "integer",   default = 5000L),
  make_option("--max_mt_pct",   type = "double",    default = 20.0)
)
opt <- parse_args(OptionParser(option_list = option_list))

tmp <- tempfile()
dir.create(tmp)
file.symlink(normalizePath(opt\$barcodes), file.path(tmp, "barcodes.tsv.gz"))
file.symlink(normalizePath(opt\$features), file.path(tmp, "features.tsv.gz"))
file.symlink(normalizePath(opt\$matrix),   file.path(tmp, "matrix.mtx.gz"))

counts <- Read10X(data.dir = tmp)

seurat <- CreateSeuratObject(
  counts       = counts,
  project      = opt\$sample,
  min.cells    = opt\$min_cells,
  min.features = opt\$min_features
)

seurat[["percent.mt"]] <- PercentageFeatureSet(seurat, pattern = "^MT-")

p_pre <- VlnPlot(seurat, features = c("nFeature_RNA", "nCount_RNA", "percent.mt"),
                 ncol = 3, pt.size = 0.1)
ggsave("qc_violin_prefilter.png", p_pre, width = 12, height = 5, dpi = 150)

p_scatter <- FeatureScatter(seurat, feature1 = "nCount_RNA", feature2 = "nFeature_RNA")
ggsave("qc_scatter.png", p_scatter, width = 6, height = 5, dpi = 150)

seurat <- subset(
  seurat,
  subset = nFeature_RNA > opt\$min_features &
           nFeature_RNA < opt\$max_features &
           percent.mt   < opt\$max_mt_pct
)

p_post <- VlnPlot(seurat, features = c("nFeature_RNA", "nCount_RNA", "percent.mt"),
                  ncol = 3, pt.size = 0.1)
ggsave("qc_violin_postfilter.png", p_post, width = 12, height = 5, dpi = 150)

qc_df <- data.frame(
  sample          = opt\$sample,
  cells_raw       = ncol(counts),
  cells_filtered  = ncol(seurat),
  median_features = median(seurat\$nFeature_RNA),
  median_counts   = median(seurat\$nCount_RNA),
  median_pct_mt   = median(seurat\$percent.mt)
)
write.csv(qc_df, "qc_stats.csv", row.names = FALSE)

saveRDS(seurat, paste0(opt\$sample, "_seurat.rds"))
message("Done. Cells retained: ", ncol(seurat))
REOF

    Rscript run_seurat.R \\
        --barcodes  ${barcodes} \\
        --features  ${features} \\
        --matrix    ${matrix} \\
        --sample    "${params.sample_name}" \\
        --min_cells ${params.min_cells} \\
        --min_features ${params.min_features} \\
        --max_features ${params.max_features} \\
        --max_mt_pct   ${params.max_mt_pct}
    """
}

workflow {
    barcodes_ch = Channel.fromPath(params.barcodes)
    features_ch = Channel.fromPath(params.features)
    matrix_ch   = Channel.fromPath(params.matrix)

    CREATE_SEURAT(barcodes_ch, features_ch, matrix_ch)
}
